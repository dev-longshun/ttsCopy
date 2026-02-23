# CLAUDE.md

## 强制协议

本项目严格遵循 `protocol-dev` 开发协议（`.claude/skills/protocol-dev/SKILL.md`）。

核心规则：**先谋后动，禁止未授权编码。**

- 任何代码变更必须先给方案，等待用户明确授权（"执行"、"做吧"、"改吧"等）后才能动手
- 授权前只能读代码、分析问题、输出方案，不能写入任何文件
- 例外：生成 commit 信息、回答技术问题、代码解释可直接执行

## 项目概要

ttsCopy — macOS 菜单栏应用，双模式接收消息并复制到剪贴板：
- Telegram 模式：Bot API 长轮询
- LAN 模式：WebSocket 服务器 + Bonjour 广播，配合手机端 App

技术栈：SwiftUI / Swift async-await / Network.framework / macOS 15+

当前分支：`feature/lan-mode`

## 关键约束

- 最低支持 macOS 15 (Sequoia)，所有 API 必须兼容
- Swift 5 语言模式 + SPM 6.0
- 禁止命令行编译（`swift build`、`xcodebuild`），提醒用户手动编译
- 禁止 `rm` 删除文件，必须用 `trash` 命令
- `git commit` 流程：先输出 commit 信息供用户审核，用户确认后再执行提交，提交内容必须与展示内容完全一致，禁止附加任何辅助编程标识信息（如 Co-Authored-By 等）
- 禁止使用 Markdown 表格，用列表替代
- 开发完成后必须输出新增/修改文件清单

## 文件结构

核心代码在 `ttsCopy/` 目录：
- `ttsCopyApp.swift` — App 入口
- `ServiceManager.swift` — 统一服务管理
- `TelegramService.swift` — Telegram 传输层
- `LANService.swift` — WebSocket + Bonjour
- `MessageProcessor.swift` — 消息处理
- `MessageTypes.swift` — 共享类型
- `MenuBarView.swift` / `SettingsView.swift` — UI

详细架构见 `DEVELOPMENT.md`。
