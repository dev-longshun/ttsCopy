# 回复格式规范

## 禁止使用 Markdown 表格

由于对话框不支持表格渲染，所有需要对比或列举的信息，请使用以下替代格式：

- **列表形式**：用无序列表或有序列表展示
- **分组描述**：用加粗标题 + 缩进描述的方式
- **对比格式**：使用 `A vs B` 或分段描述的方式

## 功能对比示例（禁止用表格）

**本地词典**
- 单词释义：✅ 多个义项，按词性分类
- 音标：✅ 英式/美式
- 离线支持：✅ 完全离线

**系统翻译**
- 单词释义：⚠️ 只返回一个翻译结果
- 音标：❌ 不提供
- 离线支持：⚠️ 需下载语言包

## 文件修改清单格式

需要修改的文件：
- `SettingsView.swift`：添加翻译引擎选择 UI
- `DictionaryService.swift`：添加翻译模式枚举和切换逻辑
- `FloatingWordCard.swift`：适配不同数据源的 UI 显示

## 方案输出规范

在提出技术方案时，文件清单必须遵循以下格式：

### 新增文件

必须标注完整的文件路径（从项目根目录开始）和 Xcode 项目中的添加位置

示例：

- `ttsCopy/TelegramService.swift`：Telegram API 与长轮询逻辑
  - Xcode 位置：ttsCopy → ttsCopy
- `ttsCopy/MenuBarView.swift`：菜单栏弹窗与最近消息
  - Xcode 位置：ttsCopy → ttsCopy
- `ttsCopy/SettingsView.swift`：设置页与 Token 配置
  - Xcode 位置：ttsCopy → ttsCopy

### 修改文件

同样标注完整路径

示例：

- `BookWorm/BookWorm/Views/HomeView.swift`：添加阅读目标模块

### 执行后提醒

创建新文件后，必须提醒用户：

1. 将文件添加到 Xcode 项目中
2. 说明具体的添加位置（项目导航器中的文件夹路径）
3. 确认 Target Membership 正确（如 BookWorm）
