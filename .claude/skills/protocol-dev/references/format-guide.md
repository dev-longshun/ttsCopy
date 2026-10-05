# 回复格式规范

## 禁止使用 Markdown 表格

由于对话框不支持表格渲染，所有需要对比或列举的信息，请使用以下替代格式：

- **列表形式**：用无序列表或有序列表展示
- **分组描述**：用加粗标题 + 缩进描述的方式
- **对比格式**：使用 `A vs B` 或分段描述的方式

## 功能对比示例（禁止用表格）

**Telegram 长轮询（当前方案）**
- 消息来源：主动调用 getUpdates
- 网络要求：能访问外网即可，不需要公网地址
- 延迟：取决于网络状况

**Telegram Webhook**
- 消息来源：Telegram 主动推送到服务器
- 网络要求：需要公网 HTTPS 地址
- 延迟：低

## 文件修改清单格式

需要修改的文件：
- `ttsCopy/ServiceManager.swift`：添加新功能集成
- `ttsCopy/MenuBarView.swift`：添加 UI 控件
- `ttsCopy/SettingsView.swift`：添加设置项

## 方案输出规范

在提出技术方案时，文件清单必须遵循以下格式：

### 新增文件

必须标注完整的文件路径（从项目根目录开始）

示例：

- `ttsCopy/Models/NewModel.swift`：新数据模型
- `ttsCopy/Services/NewService.swift`：新服务

### 修改文件

同样标注完整路径

示例：

- `ttsCopy/ServiceManager.swift`：添加新功能集成

### 执行后提醒

创建新文件后，提醒用户：

1. 确认文件在 `ttsCopy/` 目录下（SPM 会自动包含）
2. 如果文件在 `exclude` 列表中的路径，需要更新 `Package.swift`
3. 手动编译验证（禁止命令行编译）
