# TTS Copy

一个 macOS 菜单栏应用，自动将 Telegram 群组消息复制到剪贴板。

## 功能特性

- 菜单栏常驻，不占用 Dock 位置
- 监听 Telegram Bot 消息，自动复制到剪贴板
- 收到消息时弹出系统通知
- 支持过滤指定群组的消息
- 消息历史记录（最近 20 条）
- 支持开机自启动

## 使用方法

### 1. 创建 Telegram Bot

1. 在 Telegram 中搜索 `@BotFather`
2. 发送 `/newbot` 命令
3. 按提示设置 Bot 名称和用户名
4. 获取 Bot Token（形如 `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`）

### 2. 设置群组

1. 创建一个 Telegram 群组（或使用现有群组）
2. 将你的 Bot 添加到群组中
3. **重要**：在群组设置中，将 Bot 设为管理员，或者发送任意消息 @ 你的 Bot

### 3. 配置应用

1. 用 Xcode 打开 `ttsCopy.xcodeproj`
2. 按 `Cmd + R` 运行应用
3. 点击菜单栏图标，打开设置
4. 输入你的 Bot Token
5. 点击「开始监听」

### 4. 获取 Chat ID

1. 在手机上给群组发送一条消息
2. 在 Mac 应用的「最近消息」列表中可以看到 Chat ID
3. 将 Chat ID 添加到允许列表中（或开启「接收所有消息」）

## 编译运行

### 方式一：Xcode（推荐）

```bash
open ttsCopy.xcodeproj
```

然后按 `Cmd + R` 运行。

### 方式二：命令行编译

```bash
xcodebuild -project ttsCopy.xcodeproj -scheme ttsCopy -configuration Release build
```

编译后的应用在 `build/Release/ttsCopy.app`

## 系统要求

- macOS 13.0 或更高版本
- Xcode 15.0 或更高版本（用于编译）

## 技术栈

- SwiftUI
- Telegram Bot API（长轮询方式）
- UserNotifications（系统通知）
- NSPasteboard（剪贴板操作）

## 隐私说明

- 所有数据保存在本地（UserDefaults）
- 不收集任何用户信息
- Bot Token 仅用于调用 Telegram API

## 许可证

MIT License
