# ttsCopy 开发文档

## 项目概述

ttsCopy 是一个 macOS 菜单栏应用，用于自动接收消息并复制到剪贴板。支持两种工作模式：

- **Telegram 模式**：通过 Telegram Bot API 长轮询接收消息
- **LAN 模式**：在局域网内运行 WebSocket 服务器，配合手机端 React Native App 使用

## 技术栈

| 组件 | 技术 |
|------|------|
| 平台 | macOS 15+ (Sequoia) |
| UI | SwiftUI |
| 并发 | Swift async/await |
| 网络 (Telegram) | URLSession |
| 网络 (LAN) | Network.framework (NWListener + WebSocket) |
| 服务发现 | Bonjour (mDNS), 服务类型 `_ttscopy._tcp` |
| 翻译 | Apple Translation framework |
| 通知 | UserNotifications |
| 剪贴板 | NSPasteboard |
| 持久化 | UserDefaults |
| 构建 | Swift Package Manager 6.0, Swift 5 语言模式 |

## 架构设计

```
┌─────────────────────────────────────────────────┐
│                   SwiftUI UI                     │
│  MenuBarView / SettingsView / ttsCopyApp         │
│         ↕ @EnvironmentObject                     │
├─────────────────────────────────────────────────┤
│              ServiceManager                      │
│  统一状态管理 (@Published)                        │
│  模式切换 / 服务生命周期 / UserDefaults 持久化     │
│         ↕ callbacks                              │
├──────────────────┬──────────────────────────────┤
│ TelegramService  │         LANService            │
│ Bot API 长轮询    │  WebSocket Server + Bonjour   │
│         ↕        │              ↕                │
│  Telegram API    │   React Native App (手机端)    │
├──────────────────┴──────────────────────────────┤
│              MessageProcessor                    │
│  剪贴板 / 通知 / 翻译 / 图片保存                   │
└─────────────────────────────────────────────────┘
```

## 文件结构

```
ttsCopy/
├── Package.swift                 # SPM 配置 (swift-tools-version 6.0, macOS 15)
├── ttsCopy/
│   ├── ttsCopyApp.swift          # App 入口, AppDelegate, 菜单栏初始化
│   ├── MessageTypes.swift        # 共享类型: ServiceMode, ConnectionStatus, MessageContent, MessageItem
│   ├── MessageProcessor.swift    # 消息处理: 剪贴板/通知/翻译/图片保存
│   ├── ServiceManager.swift      # 统一服务管理, @EnvironmentObject
│   ├── TelegramService.swift     # Telegram Bot API 传输层
│   ├── LANService.swift          # 局域网 WebSocket 服务器 + Bonjour
│   ├── MenuBarView.swift         # 菜单栏弹出视图
│   ├── SettingsView.swift        # 设置界面
│   ├── Info.plist                # Bonjour 服务声明, 局域网权限描述
│   ├── ttsCopy.entitlements      # 网络权限 (client + server)
│   └── Assets.xcassets/          # 应用图标
└── ttsCopy.xcodeproj/            # Xcode 工程
```
## 消息协议 (WebSocket)

LAN 模式下，手机端与 Mac 端通过 WebSocket 通信，使用以下 JSON 协议：

### 发送文本消息
```json
// Text frame
{"type": "text", "content": "消息内容", "sender": "iPhone"}
```

### 发送图片消息 (两帧)
```json
// 第一帧: Text frame (元数据)
{"type": "image", "caption": "可选说明", "sender": "iPhone"}

// 第二帧: Binary frame (图片二进制数据, JPEG/PNG)
<raw image bytes>
```

### 服务端响应
```json
// Text frame
{"type": "status", "copied": true}
```

## 数据流

```
消息源 (Telegram API / 手机 App)
       ↓
传输层 (TelegramService / LANService)
       ↓ onMessage callback
ServiceManager
       ↓
MessageProcessor.process()
       ├─→ 文本消息
       │   ├─→ translateText() [如果开启翻译]
       │   ├─→ copyToClipboard()
       │   ├─→ sendNotification() [如果开启通知]
       │   └─→ onMessageProcessed → addMessage → UI 更新
       │
       └─→ 图片消息
           ├─→ translateText(caption) [如果开启翻译]
           ├─→ copyImageToClipboard()
           ├─→ saveImageToFile() [如果开启自动保存]
           ├─→ sendNotification() [如果开启通知]
           └─→ onMessageProcessed → addMessage → UI 更新
```

---

## 开发进度

### Phase 1: Mac 端重构 + LAN 服务 ✅ 已完成

分支: `feature/lan-mode`

| 任务 | 状态 | 说明 |
|------|------|------|
| 提取共享类型 MessageTypes.swift | ✅ | ServiceMode, ConnectionStatus, MessageContent, MessageItem |
| 提取消息处理 MessageProcessor.swift | ✅ | 剪贴板/通知/翻译/图片保存逻辑从 TelegramService 中分离 |
| 创建 ServiceManager.swift | ✅ | 统一 @EnvironmentObject, 管理双模式切换 |
| 重构 TelegramService.swift | ✅ | 精简为纯传输层, 通过回调与 ServiceManager 通信 |
| 创建 LANService.swift | ✅ | NWListener WebSocket 服务器 + Bonjour 广播 |
| 更新 UI (MenuBarView/SettingsView) | ✅ | 模式切换 Picker, LAN 状态显示, 条件化设置项 |
| 更新 ttsCopyApp.swift | ✅ | AppDelegate 使用 ServiceManager |
| 更新权限和配置 | ✅ | network.server 权限, Bonjour 服务声明 |
| 编译验证 | ✅ | swift build 通过, 零 warning |

### Phase 2: Mac 端测试与完善 🔲 待开发

| 任务 | 状态 | 说明 |
|------|------|------|
| Telegram 模式回归测试 | 🔲 | 确认重构后 Telegram 功能完整 |
| LAN 模式端到端测试 | 🔲 | 用 websocat 等工具模拟客户端连接 |
| 多设备同时连接测试 | 🔲 | 验证多个手机同时连接的稳定性 |
| 断线重连处理 | 🔲 | 客户端断开后清理连接, 服务端异常恢复 |
| 大图片传输优化 | 🔲 | 测试大文件传输, 考虑分片或压缩 |
| 添加新文件到 Xcode project | 🔲 | 将 4 个新 Swift 文件加入 xcodeproj |

### Phase 3: React Native 手机端 App 🔲 待开发

| 任务 | 状态 | 说明 |
|------|------|------|
| 初始化 RN 项目 (Expo) | 🔲 | `npx create-expo-app ttsCopy-mobile` |
| Bonjour 服务发现 | 🔲 | 集成 `react-native-zeroconf`, 自动扫描 `_ttscopy._tcp` |
| WebSocket 连接管理 | 🔲 | 使用 RN 内置 WebSocket API, 自动重连 |
| 文本发送功能 | 🔲 | 输入框 + 发送按钮, JSON text frame |
| 图片发送功能 | 🔲 | 相机拍照 / 相册选图, 元数据帧 + 二进制帧 |
| 发送状态反馈 | 🔲 | 接收服务端 status 响应, 显示"已复制"提示 |
| 连接状态 UI | 🔲 | 显示连接状态, 已发现的 Mac 列表 |
| 设备选择 | 🔲 | 多台 Mac 时选择目标设备 |

### Phase 4: 体验优化 🔲 待开发

| 任务 | 状态 | 说明 |
|------|------|------|
| Mac 端 QR Code 显示 | 🔲 | 生成包含 ws://ip:port 的二维码, 手机扫码快速连接 |
| 剪贴板历史同步 | 🔲 | Mac 剪贴板变化时推送到手机端 (双向同步) |
| 文件传输支持 | 🔲 | 支持发送任意文件, 不限于图片 |
| 加密通信 | 🔲 | TLS/WSS 加密 WebSocket 连接 |
| 配对认证 | 🔲 | 首次连接时配对确认, 防止局域网内未授权访问 |
| 深色模式适配 | 🔲 | RN App 深色/浅色主题 |
| 国际化 | 🔲 | 中英文界面切换 |

---

## 本地开发

### 构建 Mac 端
```bash
cd ttsCopy-lan
swift build
```

### 测试 LAN 模式 (无需手机)
```bash
# 安装 websocat (WebSocket 命令行工具)
brew install websocat

# 启动 app 后, 切换到 LAN 模式并启动服务
# 查看 UI 上显示的端口号, 然后:
websocat ws://localhost:<port>

# 发送文本消息
{"type":"text","content":"hello from terminal","sender":"test"}

# 预期收到响应:
{"type":"status","copied":true}
# 同时 Mac 剪贴板应包含 "hello from terminal"
```

### 测试图片发送
```bash
# websocat 不方便发送二进制帧, 建议用 Python 脚本:
python3 -c "
import asyncio, websockets, json

async def test():
    async with websockets.connect('ws://localhost:<port>') as ws:
        # 发送图片元数据
        await ws.send(json.dumps({'type':'image','caption':'test img','sender':'py'}))
        # 发送图片二进制数据
        with open('test.jpg', 'rb') as f:
            await ws.send(f.read())
        # 接收响应
        print(await ws.recv())

asyncio.run(test())
"
```

### Git 分支
- `main`: 原始 Telegram-only 版本
- `feature/lan-mode`: 双模式版本 (当前开发分支)


