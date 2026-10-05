# TTS Copy

macOS 菜单栏应用，支持两种方式将消息自动复制到剪贴板：

- **Telegram 模式** —— 监听 Telegram Bot 消息
- **LAN 模式** —— 局域网内配合手机端 App，直接发送文字和图片到 Mac 剪贴板

## 功能特性

- 菜单栏常驻，不占用 Dock 位置
- 双模式切换：Telegram / LAN
- 文本消息自动复制到剪贴板
- 图片消息复制到剪贴板 + 可选自动保存到本地
- 自动翻译（中文 → 英文，基于 Apple Translation）
- 提示词优化（可选，基于 OpenAI 接口，处理后再写入剪贴板）
- 收到消息时弹出系统通知
- 消息历史记录（最近 20 条）

### LAN 模式

- WebSocket 服务器，手机通过 WiFi 直接连接
- Bonjour (mDNS) 自动广播，手机可自动发现
- 支持多设备同时连接
- 配套 Android App（React Native / Expo）

### Telegram 模式

- Telegram Bot API 长轮询
- 支持过滤指定群组
- 支持开机自启动

## 系统要求

- macOS 15.0 (Sequoia) 或更高版本
- Xcode 16.0 或更高版本（用于编译）

## 项目结构

```
ttsCopy-lan/
├── Package.swift                 # SPM 配置
├── ttsCopy.xcodeproj/            # Xcode 工程
├── ttsCopy/
│   ├── ttsCopyApp.swift          # App 入口，菜单栏初始化
│   ├── MessageTypes.swift        # 共享类型定义
│   ├── MessageProcessor.swift    # 消息处理（剪贴板/通知/翻译/图片保存）
│   ├── ServiceManager.swift      # 统一服务管理
│   ├── TelegramService.swift     # Telegram Bot API 传输层
│   ├── LANService.swift          # WebSocket 服务器 + Bonjour 广播
│   ├── MenuBarView.swift         # 菜单栏弹出视图
│   ├── SettingsView.swift        # 设置界面
│   ├── Info.plist
│   ├── ttsCopy.entitlements
│   └── Assets.xcassets/
├── 编译运行指南.md                 # 零基础编译运行教程
└── DEVELOPMENT.md                # 开发文档（架构/协议/进度）
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

whisper.cpp 版本固定在 `scripts/build-whisper.sh` 的 `WHISPER_CPP_REF`，升级时改这里。

## 使用方法

### LAN 模式（推荐）

1. 运行 Mac 端 App
2. 点击菜单栏图标，切换到"LAN 模式"
3. 点击"启动服务"
4. 在手机上打开配套 App，输入 Mac 上显示的 IP 和端口号连接
5. 在手机上发送文字或图片，Mac 剪贴板自动更新

手机端 App 项目：[ttsCopy-mobile](../ttsCopy-mobile/)

### 语音识别内存占用

Whisper 模型不会在启动时加载：手机开始录音时在后台加载，识别后闲置 5 分钟、或手机全部断开 30 秒后自动释放。平时 App 只占几十 MB 内存。不用的模型可以在设置 →「已下载的模型」里删除（移到废纸篓）。

### 提示词优化

1. 打开设置，开启“提示词优化（OpenAI）”
2. 填写 `OpenAI API Key`、`Base URL` 和 `Model`
3. 收到文本消息后，应用会先调用 OpenAI 优化提示词
4. 如果同时开启自动翻译，会在优化后继续翻译，再写入剪贴板
5. 优化模板放在 `ttsCopy/PromptOptimizerSystemPrompt.md`，后续可直接在项目里修改

### Telegram 模式

1. 在 Telegram 中通过 @BotFather 创建 Bot，获取 Token
2. 将 Bot 添加到目标群组并设为管理员
3. 运行 App，在设置中输入 Bot Token
4. 切换到"Telegram 模式"，点击"开始监听"
5. 在群组中发送消息，Mac 剪贴板自动更新

## WebSocket 协议

LAN 模式下手机与 Mac 通过 WebSocket 通信：

```jsonc
// 发送文本
{"type": "text", "content": "消息内容", "sender": "Android"}

// 发送图片（两帧：先 JSON 元数据，再 binary 图片数据）
{"type": "image", "caption": "可选说明", "sender": "Android"}
<binary frame: 图片字节>

// 服务端响应
{"type": "status", "copied": true}
```

Bonjour 服务类型：`_ttscopy._tcp`

## 技术栈

| 组件 | 技术 |
|------|------|
| UI | SwiftUI |
| 并发 | Swift async/await |
| 网络 (LAN) | Network.framework (NWListener + WebSocket) |
| 服务发现 | Bonjour (mDNS) |
| 网络 (Telegram) | URLSession |
| 翻译 | Apple Translation framework |
| 提示词优化 | OpenAI Chat Completions API |
| 通知 | UserNotifications |
| 剪贴板 | NSPasteboard |
| 持久化 | UserDefaults |
| 构建 | Swift Package Manager 6.0 |

## 隐私说明

- 所有数据保存在本地
- LAN 模式仅在局域网内通信，不经过任何外部服务器
- Telegram 模式的 Bot Token 仅用于调用 Telegram API

## 许可证

MIT License
