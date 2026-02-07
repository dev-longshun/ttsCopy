# macOS 版本兼容性规范（ttsCopy 项目）

在编写任何 macOS / SwiftUI / AppKit 代码之前，**必须先确认项目的最低支持版本**，避免使用不兼容的 API。

## 当前项目配置

- **最低支持版本**：macOS 13.0
- **配置位置**：`ttsCopy.xcodeproj/project.pbxproj` 中的 `MACOSX_DEPLOYMENT_TARGET`

## 强制检查流程

1. **方案设计阶段**：若涉及 SwiftUI/AppKit 新特性或系统 API，在方案中说明该 API 的最低支持版本
2. **编码阶段**：使用的所有 API 需兼容 macOS 13.0
3. **如需使用更新版本 API**：使用 `@available` 或 `if #available` 做条件判断，并说明低版本降级方式

## 本项目常用 API 与版本

- **SwiftUI / AppKit**：菜单栏（NSStatusItem、NSPopover）、SwiftUI 视图、UserNotifications、NSPasteboard — macOS 13 均可用
- **Telegram Bot API**：为网络请求，与系统版本无关
- **ServiceManagement (SMAppService)**：开机自启动在 macOS 13+ 使用新 API，若需兼容更早版本需单独处理

## 严禁行为

- 不查版本直接使用仅在新系统可用的 API
- 假设用户使用最新 macOS 版本

## 正确做法

- 方案设计时主动说明 API 兼容性
- 优先使用兼容当前 MACOSX_DEPLOYMENT_TARGET 的实现
- 若必须使用新 API，在方案中说明并给出降级或提示升级的方案
