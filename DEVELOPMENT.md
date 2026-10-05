# ttsCopy 开发文档

## 项目概述

ttsCopy 是一个 macOS 菜单栏应用：通过 Telegram Bot API 长轮询接收消息，收到后自动复制到剪贴板。

## 技术栈

- 平台：macOS 15+ (Sequoia)
- UI：SwiftUI
- 并发：Swift async/await
- 网络：URLSession（Telegram Bot API 长轮询）
- 通知：UserNotifications
- 剪贴板：NSPasteboard
- 持久化：UserDefaults
- 构建：Xcode 工程 + Swift Package Manager 6.0，Swift 5 语言模式

## 架构设计

```
MenuBarView / SettingsView / ttsCopyApp    SwiftUI，@EnvironmentObject 注入
    │
    ├── ServiceManager          状态管理、监听启停、设置持久化
    │     ├── TelegramService   Bot API 长轮询、Chat ID 过滤、409 冲突检测
    │     └── MessageProcessor  剪贴板、通知、图片保存
    │
    └── UpdaterController       检查 / 下载 / 校验签名 / 安装更新（GitHub Releases）
```

## 文件结构

```
ttsCopy/
├── Package.swift                    # SPM 配置 (swift-tools-version 6.0, macOS 15)
├── ttsCopy/
│   ├── ttsCopyApp.swift             # App 入口, AppDelegate, 菜单栏图标与面板
│   ├── MessageTypes.swift           # 共享类型: ConnectionStatus, ClipboardProcessingState, MessageContent, MessageItem
│   ├── MessageProcessor.swift       # 消息处理: 剪贴板/通知/图片保存
│   ├── ServiceManager.swift         # 统一服务管理, @EnvironmentObject
│   ├── TelegramService.swift        # Telegram Bot API 传输层
│   ├── UpdaterController.swift      # 应用内更新
│   ├── MenuBarView.swift            # 菜单栏弹出视图
│   ├── SettingsView.swift           # 设置界面
│   ├── Info.plist                   # 最低系统版本
│   ├── ttsCopy.entitlements         # 网络权限 (client)
│   └── Assets.xcassets/             # 应用图标
├── .github/workflows/build-dmg.yml  # CI: 编译 → 签名 → 公证 → DMG → GitHub Release
└── ttsCopy.xcodeproj/               # Xcode 工程
```

## 数据流

```
Telegram API (getUpdates 长轮询)
       ↓
TelegramService（Chat ID 过滤）
       ↓ onMessage callback
ServiceManager
       ↓
MessageProcessor.process()
       ├─→ 文本消息
       │   ├─→ onMessageProcessed → addMessage → UI 更新
       │   ├─→ copyToClipboard()
       │   ├─→ onClipboardStateChange(.completed) → 菜单栏图标亮绿勾 2 秒
       │   └─→ sendNotification() [如果开启通知]
       │
       └─→ 图片消息
           ├─→ onMessageProcessed → addMessage → UI 更新
           ├─→ copyImageToClipboard()（图片 + 说明文字）
           ├─→ saveImageToFile() [如果开启自动保存]
           ├─→ onClipboardStateChange(.completed)
           └─→ sendNotification() [如果开启通知]
```

## Telegram 冲突处理

同一个 Bot 同一时间只允许一处 getUpdates。TelegramService 在 120 秒内收到 2 次 409 即判定为冲突：停止轮询并回调 onConflict，ServiceManager 把状态置为错误并发系统通知，面板显示「在本机接管」按钮，点击后重新开始监听（会把另一台设备挤掉）。偶发一次 409（比如刚重启、旧的长轮询还没断）只等 3 秒重试。

## 本地开发

- 用 Xcode 打开 `ttsCopy.xcodeproj`，`Cmd + R` 运行
- Xcode 调试版不会自动检查更新，也不会在应用内安装更新
- 发版流程见 README「发版」一节

## 历史

LAN 模式（WebSocket + Bonjour）、语音识别（whisper.cpp）、自动翻译、提示词优化（OpenAI）已在 `refactor/telegram-only` 分支移除，需要时可从 `cb60069` 及之前的提交找回。
