# TTS Copy

macOS 菜单栏应用：监听 Telegram Bot 消息，收到后自动复制到剪贴板。

## 功能特性

- 菜单栏常驻，不占用 Dock 位置
- Telegram Bot API 长轮询接收消息，可只接收指定群组/聊天
- 文本消息自动复制到剪贴板
- 图片消息复制到剪贴板 + 可选自动保存到本地
- 收到消息时弹出系统通知
- 消息历史记录（最近 20 条）
- 同一个 Bot 被另一台 Mac 占用时自动停止监听，可一键在本机接管
- 应用内自动更新
- 支持开机自启动

## 系统要求

- macOS 15.0 (Sequoia) 或更高版本，Apple Silicon（发布包只含 arm64）
- Xcode 16.0 或更高版本（用于编译）

## 项目结构

```
ttsCopy/
├── Package.swift                    # SPM 配置
├── ttsCopy.xcodeproj/               # Xcode 工程
├── ttsCopy/
│   ├── ttsCopyApp.swift             # App 入口，菜单栏初始化
│   ├── MessageTypes.swift           # 共享类型定义
│   ├── MessageProcessor.swift       # 消息处理（剪贴板/通知/图片保存）
│   ├── ServiceManager.swift         # 统一服务管理
│   ├── TelegramService.swift        # Telegram Bot API 传输层
│   ├── UpdaterController.swift      # 应用内更新
│   ├── MenuBarView.swift            # 菜单栏弹出视图
│   ├── SettingsView.swift           # 设置界面
│   ├── Info.plist
│   ├── ttsCopy.entitlements
│   └── Assets.xcassets/
├── .github/workflows/build-dmg.yml  # CI：编译、签名、公证、发版
├── 编译运行指南.md                    # 零基础编译运行教程
└── DEVELOPMENT.md                   # 开发文档（架构/数据流）
```

## 安装与更新

从本仓库 [Releases](https://github.com/dev-longshun/ttsCopy/releases) 下载最新的 `ttsCopy-*.dmg`，打开后把 `ttsCopy.app` 拖进「应用程序」即可。安装包已经过 Developer ID 签名和苹果公证，双击就能打开。

之后的更新在 App 内完成：

- 启动时、每 30 分钟、打开菜单栏面板时（距上次检查超过 10 分钟）会在后台检查 GitHub Releases
- 发现新版本时，菜单栏图标出现红点并弹出系统通知
- 在面板里点「更新并重启」，App 会下载新版、校验签名、替换自身并重新打开
- 设置 →「软件更新」可以关闭自动检查，或手动检查

> 只在一台 Mac 上使用：Telegram Bot 同一时间只允许一处监听。两台 Mac 同时监听同一个 Bot 时，App 会提示「另一台设备正在使用这个 Bot」并停止本机监听，需要时点「在本机接管」。

## 编译运行

用 Xcode 打开 `ttsCopy.xcodeproj`，按 `Cmd + R` 运行。Xcode 调试版不会自动检查更新，也不会在应用内安装更新。

> 详细的零基础教程见 [编译运行指南.md](编译运行指南.md)

## 发版

push 到 `main` 会触发 `.github/workflows/build-dmg.yml`：编译 → Developer ID 签名 → 公证 → 打 DMG → 发布 GitHub Release，版本号为 `<MARKETING_VERSION>.<运行序号>`（如 `1.0.4.12`）。只改文档（README、DEVELOPMENT.md 等）不会发版。

首次使用前，在仓库 Settings → Secrets and variables → Actions 中配置：

- `DEVELOPER_ID_P12`：「Developer ID Application」证书（含私钥）导出的 `.p12`，base64 编码
- `DEVELOPER_ID_P12_PASSWORD`：导出 `.p12` 时设置的密码
- `APPLE_ID`：Apple 开发者账号邮箱
- `APPLE_APP_PASSWORD`：在 appleid.apple.com 生成的 App 专用密码

## 使用方法

1. 在 Telegram 中通过 @BotFather 创建 Bot，获取 Token
2. 将 Bot 添加到目标群组并设为管理员
3. 运行 App，在设置中输入 Bot Token，可先点「测试连接」确认
4. 点击菜单栏图标，再点「开始监听」（之后启动 App 会自动开始监听）
5. 在群组或与 Bot 的私聊中发送消息，Mac 剪贴板自动更新

只想接收部分群组的消息：在设置 →「允许的群组/聊天」里关闭「接收所有消息」，再添加对应的 Chat ID。

## 技术栈

- UI：SwiftUI
- 并发：Swift async/await
- 网络：URLSession（Telegram Bot API）
- 通知：UserNotifications
- 剪贴板：NSPasteboard
- 持久化：UserDefaults
- 构建：Xcode 工程 + Swift Package Manager 6.0（Swift 5 语言模式）

## 隐私说明

- 所有数据保存在本地
- Bot Token 仅用于调用 Telegram API

## 许可证

MIT License
