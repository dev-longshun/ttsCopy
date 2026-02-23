# Commit 信息生成规范（ttsCopy 项目）

## 规范要求 (Angular + Gitmoji 混合风格)

### 1. 格式结构

`<type>(<scope>): <emoji> <subject>`

- `scope` 是可选的，如果更改涉及特定模块请填写，否则省略括号
- `subject` 使用简体中文描述变更

### 1.1 本项目 Scope 约定

按变更涉及的主要模块选用，便于回溯：

- `app`：应用入口、AppDelegate、菜单栏生命周期（ttsCopyApp.swift）
- `telegram`：Telegram API、长轮询、消息解析（TelegramService.swift）
- `menubar`：菜单栏弹窗、最近消息列表（MenuBarView.swift）
- `settings`：设置页、Token/Chat ID 配置、测试连接（SettingsView.swift）
- `clipboard`：剪贴板、通知开关等与复制/通知相关的逻辑
- `chore` / 无 scope：构建、Git、依赖、文档、通用工具

### 2. Type 与 Emoji 的对应关系

- `feat` -> ✨ (新功能)
- `fix` -> 🐛 (修复 Bug)
- `docs` -> 📝 (文档变动)
- `style` -> 💄 (格式/样式调整，不影响逻辑)
- `refactor` -> ♻️ (重构)
- `perf` -> ⚡️ (性能优化)
- `test` -> ✅ (测试相关)
- `chore` -> 🔧 (构建/工具/依赖变动)
- `revert` -> ⏪ (回退)

### 3. 内容来源（强制执行 Git Diff 验证）

**🚨 必须先执行 `git diff --name-only HEAD` 和 `git diff HEAD --stat` 查看实际变更的文件**

**关键要求**：
- **明确范围**：`HEAD` 代表上一次 commit，所以 diff 显示的是"从上次提交到现在的所有变更"，**不是**本次对话中的修改
- **严禁仅根据对话上下文猜测或总结变更内容**
- 根据 diff 结果，逐一分析每个变更文件的实际修改内容
- 如果 diff 显示的变更与对话上下文不一致，以 diff 结果为准
- **只描述最终实现的功能，不要包含探索过程中的失败尝试或被放弃的方案**
- 如果变更较为复杂，请在 Header 之后生成详细的 Body 描述（Markdown 列表形式）

**调试代码检查**：
- 在生成 commit 信息前，主动检查 diff 中是否包含调试日志（如 `print("🔬")`、`debugLog` 等）
- 如有则主动询问用户是否需要清理
- 只有清理后才生成最终的 commit 信息

### 4. 输出形式

必须输出**三个代码块**，方便在 Git GUI 工具中分别复制：

**代码块 1 - 完整版**：Header + Body 的完整 commit 信息

**代码块 2 - Summary**：只有 Header 行（用于 Git GUI 的 "Commit summary" 输入框）

**代码块 3 - Description**：只有 Body 部分（用于 Git GUI 的 "Description" 输入框，如果没有 Body 则输出"无"）

**输出后必须主动询问用户是否执行提交**（如"确认无误，是否执行提交？"），不要等用户主动说"执行"。

commit 信息除了 type 和 scope 部分可以使用英文，其余部分需使用简体中文书写

### 5. 输出示例（ttsCopy 项目）

**完整版**：

```
feat(menubar): ✨ 菜单栏增加通知开关

- TelegramService 新增 showNotification 配置并持久化
- MenuBarView 增加「收到消息时显示通知」开关
- 仅在开启时发送系统通知
```

**Summary**：

```
feat(menubar): ✨ 菜单栏增加通知开关
```

**Description**：

```
- TelegramService 新增 showNotification 配置并持久化
- MenuBarView 增加「收到消息时显示通知」开关
- 仅在开启时发送系统通知
```

**其他示例**：
- `fix(telegram): 🐛 修复 404 时未给出明确错误提示`
- `chore: 🔧 初始化 Git 仓库并添加 .gitignore`
- `docs: 📝 更新 README 使用说明与 Chat ID 获取步骤`

### 6. 禁止事项

- 不要提及"移除"、"删除"等在本次提交前不存在的功能或组件
- 不要描述探索过程中的错误路径或失败尝试
- 不要包含调试信息、临时代码等开发过程中的中间状态
- **严禁不查看 git diff 就直接根据对话内容生成 commit 信息**
- **严禁遗漏 diff 中显示的文件变更**
- 只描述最终交付的功能和改进
- **commit 信息必须与 git diff 结果完全对应**

## Commit 信息增强规范

对于**性能优化**或**重大功能改进**类型的提交，在 Body 部分增加"优化效果"小节。

### 格式示例

```
⚡️ perf(list): 优化生词库/语境库列表加载性能

- 缓存排序结果为 @State 变量，避免计算属性重复计算
- 创建 LazyView 包装器实现详情页懒加载
- 预计算到期时间缓存，将排序时 5000+ 次查询降为 300 次
- 修复 LazyView 使用 @autoclosure 导致状态捕获错误的 bug

优化效果：
- 生词库加载时间从 7-8 秒降至 1 秒内
- 语境库加载时间从 2-3 秒降至秒进
- 点击列表项能正确进入对应详情页
```

### 适用场景

- `perf` 类型：性能优化提交
- `feat` 类型：涉及用户体验改进的新功能
- `fix` 类型：修复影响用户体验的严重 Bug

### 优化效果描述规范

- 使用**对比形式**：从 X 降至 Y、从 A 改善到 B
- 使用**具体数据**：时间、次数、百分比等可量化指标
- 使用**用户感知语言**：秒进、流畅、无卡顿等
