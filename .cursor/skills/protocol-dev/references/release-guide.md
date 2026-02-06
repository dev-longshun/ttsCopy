# 版本发布流程规范

## 触发条件

当用户说"准备发布新版本"、"我要发布新版本"、"准备发行版本"等时，自动执行版本发布流程。

## 🚫 严禁行为

**绝对禁止直接修改 Xcode 项目文件**：
- ❌ 禁止直接修改 `project.pbxproj` 中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`
- ❌ 禁止直接修改任何 Xcode 项目配置文件
- ❌ 禁止创建 release commit（用户需要手动提交）

**正确做法**：
- ✅ 只提供版本号和 Build ID 的更新建议
- ✅ 生成符合规范的 commit 信息供用户复制使用
- ✅ 提醒用户在 Xcode 中手动更新版本号和 Build ID
- ✅ 提醒用户手动创建 release commit

## 任务一：查找最新版本号和 Build ID

### 步骤 1：获取当前分支信息

```bash
git branch --show-current
```

### 步骤 2：查找当前分支的版本信息

1. **遍历当前分支的所有 commit**：
   ```bash
   git log --oneline --all
   ```

2. **查找包含版本号的 commit**：
   - 查找包含 `MARKETING_VERSION` 或 `CURRENT_PROJECT_VERSION` 的 commit
   - 查找包含 `chore(release): 🔖 发布 v` 的 commit（发布 commit）

3. **提取版本号和 Build ID**：
   - 从 `project.pbxproj` 文件中提取 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`
   - 从发布 commit 的 message 中提取版本号（如 `v1.1.6`）

### 步骤 3：查找分叉分支的版本信息

1. **获取所有分支**：
   ```bash
   git branch -a
   ```

2. **遍历每个分支查找版本信息**：
   - 对于每个分支，查找包含版本号的 commit
   - 检查该分支的 `project.pbxproj` 文件中的版本号

3. **比较所有分支的版本号**：
   - 使用语义化版本号比较（如 `1.1.6` vs `1.1.7`）
   - 找出最新的版本号和对应的 Build ID

### 步骤 4：输出结果

输出格式：

```
最新版本号：1.1.6
最新 Build ID：24
版本所在 commit：17289f2e7b1253ccc0ba2d05bf1d4d9b5e7287a4
```

## 任务二：生成更新日志

### 步骤 1：确定版本范围

1. **找到上一个版本发布的 commit**：
   - 查找包含 `chore(release): 🔖 发布 v` 的最新 commit
   - 记录该 commit 的 hash（如 `17289f2`）

2. **获取从该 commit 到当前 HEAD 的所有提交**：
   ```bash
   git log <上一个版本commit>..HEAD --oneline
   ```

### 步骤 2：分析提交信息

1. **按类型分类提交**：
   - `feat`：新功能
   - `fix`：问题修复
   - `perf`：性能优化
   - `refactor`：重构
   - `chore`：其他（排除 release 类型）

2. **识别同一功能的多个提交**：
   - 通过 `scope` 识别（如 `feat(export)`、`feat(vocabulary)`）
   - 通过描述关键词识别（如"实现"+"优化"、"新增"+"改进"）

3. **整合相邻的同一功能提交**：
   - 如果相邻提交的 scope 相同且描述相关，合并为一条
   - 合并时只保留最终效果描述

### 步骤 3：生成更新日志

#### 格式结构

```markdown
chore(release): 🔖 发布 v[版本号] 版本 - [版本主题描述]

- [功能点1]：[简洁描述功能和效果]
- [功能点2]：[简洁描述功能和效果]
- [功能点3]：[简洁描述功能和效果]
```

#### Header 格式

- `chore(release): 🔖 发布 v[版本号] 版本 - [主题描述]`
- 主题描述：一句话概括本次更新的核心亮点
- 示例：`chore(release): 🔖 发布 v1.1.7 版本 - 词汇导出与阅读体验优化`

#### Body 格式

- 使用无序列表（`- `）
- 每个条目一行，简洁描述功能和效果
- 格式：`[功能名称]：[效果描述]`

#### 内容整合规则

1. **合并规则**：
   - 相邻提交如果 scope 相同且描述相关，合并为一条
   - 同一功能的多个提交（如"实现"+"优化"+"修复"）合并为一条
   - 只写最终效果，不写开发过程

2. **过滤规则**：
   - ❌ 不包含开发过程中的问题（如"修复新功能的 bug"）
   - ❌ 不包含探索性提交（如"尝试"、"测试"、"调试"）
   - ❌ 不包含内部技术细节（如"重构代码结构"）
   - ✅ 只写最终交付的功能和效果
   - ✅ 突出用户价值和体验改进

3. **描述规范**：
   - 使用简体中文
   - 简洁明了，突出用户价值
   - 避免技术术语，使用用户友好的语言

#### 示例

**输入提交**：
```
feat(export): ✨ 实现 CSV 和 PDF 格式词汇导出功能
feat(export): ✨ 实现 Anki 问答题格式导出功能
feat(vocabulary): ✨ 添加生词库词汇导出功能
fix(export): 🐛 修复导出功能的 CSV 格式 bug
perf(export): ⚡️ 优化导出功能的性能
```

**输出更新日志**：
```markdown
- 词汇导出功能：支持导出生词库为 CSV、PDF 和 Anki 问答题格式
```

**注意**：多个相关提交被整合为一条，去除了开发过程中的 bug 修复和性能优化细节。

### 步骤 4：生成版本主题

根据整合后的功能点，生成一个简洁的主题描述：

- 如果主要是新功能：`[核心功能]与[其他改进]`
- 如果主要是修复：`[核心修复]与体验优化`
- 如果功能较多：`[主要功能1]、[主要功能2]与[其他改进]`

示例：
- `词汇导出与阅读体验优化`
- `精选书单与阅读体验全面升级`
- `EPUB 解析优化与界面改进`

### 步骤 5：生成 App Store 更新日志

#### 格式要求

1. **纯文本**：不能包含任何 emoji 表情符号
2. **输出方式**：放在代码块中（使用三个反引号包裹）
3. **分类顺序**：新增功能 > 功能优化 > 问题修复
4. **字符限制**：控制在 4000 字符以内（App Store 限制）

#### 格式结构

```
新增功能
- [功能点1]：[简洁描述功能和效果]
- [功能点2]：[简洁描述功能和效果]

功能优化
- [优化点1]：[简洁描述优化内容]
- [优化点2]：[简洁描述优化内容]

问题修复
- [修复点1]：[简洁描述修复内容]
- [修复点2]：[简洁描述修复内容]
```

#### 分类规则

1. **新增功能**（feat）：
   - 所有 `feat` 类型的提交
   - 描述新功能的价值和效果
   - 使用"新增功能"作为分类标题

2. **功能优化**（perf/refactor）：
   - `perf` 类型的提交（性能优化）
   - `refactor` 类型的提交（重构改进）
   - 描述优化带来的体验提升
   - 使用"功能优化"作为分类标题
   - 如果本版本没有优化类提交，则省略此分类

3. **问题修复**（fix）：
   - 所有 `fix` 类型的提交
   - 描述修复的问题和影响
   - 使用"问题修复"作为分类标题
   - 如果本版本没有修复类提交，则省略此分类

#### 内容整合规则

1. **合并规则**（与 Git commit 日志相同）：
   - 相邻提交如果 scope 相同且描述相关，合并为一条
   - 同一功能的多个提交（如"实现"+"优化"+"修复"）合并为一条
   - 只写最终效果，不写开发过程

2. **过滤规则**：
   - ❌ 不包含开发过程中的问题（如"修复新功能的 bug"）
   - ❌ 不包含探索性提交（如"尝试"、"测试"、"调试"）
   - ❌ 不包含内部技术细节（如"重构代码结构"）
   - ❌ 不包含 chore 类型的提交（除非是重要的工具改进）
   - ✅ 只写最终交付的功能和效果
   - ✅ 突出用户价值和体验改进

3. **描述规范**：
   - 使用简体中文
   - 简洁明了，突出用户价值
   - 避免技术术语，使用用户友好的语言
   - 每条描述控制在 50 字以内（建议）

#### 生成流程

1. **按照分类规则分类**：
   - 将整合后的提交分为三类：新增功能、功能优化、问题修复

2. **按顺序生成**：
   - 先写"新增功能"部分
   - 再写"功能优化"部分（如果有）
   - 最后写"问题修复"部分

3. **移除所有 emoji**：
   - 检查并移除所有 emoji 表情符号
   - 确保纯文本格式

4. **输出到代码块**：
   - 使用三个反引号包裹
   - 标记为纯文本（不指定语言）

5. **字符数检查**：
   - 统计总字符数
   - 如果超过 4000 字符，提示用户需要精简

#### 输出示例

**输入提交**（已整合）：
```
feat(export): ✨ 实现 CSV、PDF 和 Anki 格式词汇导出功能
feat(vocabulary): ✨ 生词库详情页新增英文释义模块
feat(bookSource): ✨ 新增精选书单功能，优化图书源浏览体验
feat: ✨ 添加 App Store 智能评分提示功能
fix(reader): 🐛 修复下拉退出手势在屏幕任意位置都能触发的问题
fix(library): 🐛 修复书库空状态判断忽略系列的问题
```

**输出 App Store 更新日志**：
```
新增功能
- 词汇导出功能：支持导出生词库为 CSV、PDF 和 Anki 问答题格式，方便复习和分享
- 生词库增强：详情页新增英文释义模块，帮助更好地理解单词含义
- 精选书单：新增精选书单功能，优化图书源浏览体验，快速发现优质内容
- 智能评分：添加 App Store 智能评分提示功能，在合适的时机邀请用户评分

问题修复
- 阅读体验优化：修复下拉退出手势在屏幕任意位置都能触发的问题，避免误操作
- 书库改进：修复空状态判断忽略系列的问题，正确显示空状态提示
```

#### 注意事项

- 如果某个分类下没有内容，则完全省略该分类（包括分类标题）
- 确保所有描述都是用户友好的，避免技术术语
- 每条描述都应该突出用户价值和体验改进
- 字符数控制在 4000 以内，如果超出需要精简描述

### 步骤 6：生成 App Store 审核备注

#### 格式要求

1. **纯文本**：不能包含任何 emoji 表情符号
2. **输出方式**：放在代码块中（使用三个反引号包裹）
3. **语言**：使用英文
4. **固定模板**：CORE FEATURES 和 CONTACT 部分保持不变，只更新 WHAT'S NEW IN THIS VERSION 部分

#### 格式结构

```
Dear Review Team,

Thank you for reviewing this update to Readex.

===========================================
WHAT'S NEW IN THIS VERSION
===========================================
- [更新点1]：[简洁英文描述]
- [更新点2]：[简洁英文描述]
- [更新点3]：[简洁英文描述]

===========================================
CORE FEATURES
===========================================
Readex is a reading and language-learning tool that does NOT provide or distribute any content.

Users must import their own EPUB, TXT, DOCX, or PDF files via the Files app or share sheet.

Key features include:
- Word lookup with definitions, phonetics, and TTS pronunciation
- Sentence translation (iOS 18+ on-device or Google ML Kit offline)
- Vocabulary saving and highlighting
- Context library for saved words
- Spaced repetition review
- Reading statistics
- Book grouping and series management
- iCloud sync for reading progress and collections

Free version: 3 books, 100 words, 200 contexts  
Readex Pro (subscription): Unlimited books/words/contexts, iCloud sync

No account required. Optional iCloud sync uses the user's system iCloud account.

===========================================
CONTACT
===========================================
1774885197@qq.com

Thank you!
```

#### 生成规则

1. **固定部分**（保持不变）：
   - 开头问候语："Dear Review Team," 和 "Thank you for reviewing this update to Readex."
   - CORE FEATURES 部分（完整内容，包括所有功能描述）
   - CONTACT 部分："1774885197@qq.com"
   - 结尾："Thank you!"

2. **WHAT'S NEW IN THIS VERSION 部分**（每次更新）：
   - 基于 App Store 更新日志（步骤 5 的输出）生成
   - 将中文更新日志翻译成英文
   - 使用简洁的英文描述
   - 格式：`- [功能/修复点]：[描述]`
   - 按分类顺序：新增功能 > 功能优化 > 问题修复
   - 不写分类标题，直接列出所有条目

#### 翻译规则

1. **分类标题处理**：
   - "新增功能" → 不写标题，直接列出功能点
   - "功能优化" → 不写标题，直接列出优化点
   - "问题修复" → 不写标题，直接列出修复点

2. **描述翻译原则**：
   - 使用简洁、专业的英文
   - 突出用户价值和体验改进
   - 避免技术术语，使用用户友好的语言
   - 每条描述控制在合理长度内

3. **格式转换**：
   - 从中文更新日志的格式转换为英文
   - 保持列表格式（使用 `- `）
   - 移除中文分类标题，直接列出所有条目

#### 生成流程

1. **基于 App Store 更新日志**：
   - 读取步骤 5 生成的中文更新日志
   - 提取所有功能点、优化点和修复点

2. **翻译为英文**：
   - 将每条描述翻译成简洁的英文
   - 保持用户友好的语言风格
   - 确保专业性和准确性

3. **组装完整备注**：
   - 添加固定的开头部分
   - 插入 WHAT'S NEW IN THIS VERSION（英文版本，不包含分类标题）
   - 添加固定的 CORE FEATURES 部分（完整内容）
   - 添加固定的 CONTACT 部分
   - 添加固定的结尾

4. **输出到代码块**：
   - 使用三个反引号包裹
   - 标记为纯文本（不指定语言）

#### 输出示例

**基于当前提交生成的审核备注**：

```
Dear Review Team,

Thank you for reviewing this update to Readex.

===========================================
WHAT'S NEW IN THIS VERSION
===========================================
- Vocabulary export: Added support for exporting vocabulary to CSV, PDF, and Anki question formats
- Vocabulary enhancement: Added English definitions module to vocabulary detail page
- Curated booklists: New curated booklist feature to improve book source browsing experience
- Smart rating: Added App Store intelligent rating prompt feature
- Reading experience: Fixed pull-to-exit gesture triggering anywhere on screen
- Library improvement: Fixed empty state detection ignoring book series

===========================================
CORE FEATURES
===========================================
Readex is a reading and language-learning tool that does NOT provide or distribute any content.

Users must import their own EPUB, TXT, DOCX, or PDF files via the Files app or share sheet.

Key features include:
- Word lookup with definitions, phonetics, and TTS pronunciation
- Sentence translation (iOS 18+ on-device or Google ML Kit offline)
- Vocabulary saving and highlighting
- Context library for saved words
- Spaced repetition review
- Reading statistics
- Book grouping and series management
- iCloud sync for reading progress and collections

Free version: 3 books, 100 words, 200 contexts  
Readex Pro (subscription): Unlimited books/words/contexts, iCloud sync

No account required. Optional iCloud sync uses the user's system iCloud account.

===========================================
CONTACT
===========================================
1774885197@qq.com

Thank you!
```

#### 注意事项

- **CORE FEATURES 和 CONTACT 部分完全固定**，每次都不变
- **只更新 WHAT'S NEW IN THIS VERSION 部分**
- 使用简洁、专业的英文
- 确保格式一致，使用 `- ` 作为列表标记
- 保持与 App Store 更新日志的内容一致（只是语言不同）
- 不包含分类标题，直接列出所有更新点

## 完整工作流程示例

1. **用户说**："准备发布新版本"

2. **执行任务一**：
   - 查找当前分支：`main`
   - 查找版本信息：遍历所有分支的 commit
   - 输出：最新版本号 `1.1.6`，Build ID `24`

3. **执行任务二**：
   - 找到上一个发布 commit：`17289f2`
   - 获取提交列表：`git log 17289f2..HEAD`
   - 分析并整合提交
   - 生成更新日志草稿

4. **展示结果**：
   - 显示最新版本号和 Build ID
   - 显示生成的 Git commit 更新日志草稿（带 emoji）
   - 显示生成的 App Store 更新日志草稿（纯文本，无 emoji，放在代码块中）
   - 显示生成的 App Store 审核备注草稿（英文，纯文本，放在代码块中）
   - **提供版本号更新建议**（严禁直接修改 Xcode 项目文件）
     - 建议新版本号（如 `1.1.7` 或 `1.2.0`）
     - 建议新 Build ID（当前 Build ID + 1）
     - 说明需要在 Xcode 中手动更新：`ttsCopy.xcodeproj` → Target ttsCopy → General → Version / Build
   - 等待用户确认或修改

5. **用户确认后**：
   - 生成符合规范的 release commit 信息（用户手动复制提交）
   - 提醒用户：
     - 在 Xcode 中手动更新版本号和 Build ID
     - 手动创建 release commit（使用生成的 commit 信息）
