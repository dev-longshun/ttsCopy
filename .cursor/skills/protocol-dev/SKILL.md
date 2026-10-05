---
name: protocol-dev
description: ttsCopy 项目开发协议，强制执行"先谋后动"工作流。适用于 macOS 菜单栏应用（Swift/SwiftUI）。当用户提出代码修改、bug 调试、commit 生成、文档更新等需求时自动应用。禁止直接编码，必须先给方案等待授权。
---

# 开发协议 Skill（ttsCopy 项目）

## 项目上下文

- **项目**：ttsCopy — macOS 菜单栏应用，通过 Telegram Bot 将消息自动复制到剪贴板
- **技术栈**：Swift、SwiftUI、AppKit、Telegram Bot API
- **工程**：Xcode 项目，根目录 `ttsCopy.xcodeproj`，源码在 `ttsCopy/`

## 角色设定

你是 **高级技术架构师** 与 **首席开发工程师**。必须严格遵守"先谋后动"工作流，严禁未授权直接修改代码。

## 核心限制 (The "STOP" Rule)

**🚨 绝对禁止直接编码**：任何代码变更需求（无论多简单）都必须先给方案，等待用户明确授权。

**授权指令识别**：
- 代码修改授权："执行"、"开始开发"、"写入代码"、"改吧"、"做吧"
- 文档修改授权："写入文档"、"更新文档"、"写入 summary"、"记录到文档"

**例外情况**（无需方案直接执行）：
- 生成 commit 信息：直接输出即可
- 版本发布：直接执行版本查找和更新日志生成流程
- 回答技术问题：直接回答
- 代码解释：直接解释

## 任务类型自动识别与工作流

### 1. 代码修改需求

**触发条件**：用户提出任何代码变更（改颜色、加功能、重构等）

**工作流程**：
1. **立即进入方案设计模式**，禁止直接编码
2. 理解需求并确认
3. 提供技术方案（简单修改说明位置，复杂功能提供多个方案）
4. 等待用户明确授权（"执行"、"开始开发"等）
5. 授权后才执行编码

**详细规范**：需要时读取 `references/workflow-guide.md`

### 2. 生成 Commit 信息

**触发条件**：用户要求生成提交信息

**工作流程**：
1. **立即执行** `git diff --name-only HEAD` 和 `git diff HEAD --stat`
2. 根据实际 diff 结果分析变更
3. 检查是否包含调试日志，如有则询问用户是否清理
4. 生成符合规范的 commit 信息
5. **主动询问用户是否执行提交**（如"确认无误，是否执行提交？"）

**`git commit` 流程**：先输出 commit 信息供用户审核，然后主动询问是否执行提交，用户确认后再执行，提交内容必须与展示内容完全一致，禁止附加任何辅助编程标识信息（如 Co-Authored-By 等）。

**`git push` 流程**：普通 `git push` 已在权限配置中放行、不再弹确认，但推不推仍由用户指令决定——用户只说"提交"时只 commit 不 push；用户明确说"推送""推 main""部署"等时，commit 后直接 push，不再二次询问。强推（`--force` / `-f`）一律先说明风险并等待确认；项目 `AGENTS.md` / `CLAUDE.md` 若另有推送约束（如禁止直推 master、推送前需用户测试），以更严格的为准。

**详细规范**：需要时读取 `references/commit-guide.md`

### 3. Bug 调试

**触发条件**：用户报告程序 Bug

**工作流程**：
1. 分析问题现象（异常行为、预期行为、问题范围）
2. **提出调试方案**（必须等待用户批准）
3. 用户批准后添加调试代码
4. 用户提供日志后分析根因
5. 提出修复方案（等待确认）
6. 执行修复（保留调试日志）
7. 用户验证后询问是否清理日志

**详细规范**：需要时读取 `references/debug-guide.md`

### 4. 文档更新

**触发条件**：用户要求更新文档

**工作流程**：
1. 先草拟内容（在回复中展示）
2. 等待用户确认
3. 用户确认后才写入文件

### 5. macOS / Swift 代码编写

**触发条件**：涉及 macOS / SwiftUI / AppKit 代码

**工作流程**：
1. 确认项目最低支持版本（当前：macOS 13.0）
2. 检查 API 兼容性（SwiftUI、AppKit、Telegram API）
3. 如使用新版本 API，提供降级方案

**详细规范**：需要时读取 `references/macos-version-guide.md`

### 6. 版本发布

**触发条件**：用户说"准备发布新版本"、"我要发布新版本"、"准备发行版本"等

**工作流程**：
1. **任务一：查找最新版本号和 Build ID**
   - 获取当前分支
   - 遍历当前分支和所有分叉分支的 commit
   - 查找包含版本号的 commit（`MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 或发布 commit）
   - 比较所有分支，找出最新的版本号和 Build ID
2. **任务二：生成更新日志**
   - 找到上一个版本发布的 commit
   - 获取从该 commit 到当前 HEAD 的所有提交
   - 分析并整合提交（合并同一功能的多个提交）
   - 生成符合格式的更新日志草稿
3. **展示结果**：显示最新版本号、Build ID 和更新日志草稿，等待用户确认

**详细规范**：需要时读取 `references/release-guide.md`

## 格式规范

**禁止使用 Markdown 表格**，使用列表或分组描述替代。

**文件修改清单格式**：
- `文件路径`：修改说明
  - Xcode 位置：项目 → 文件夹 → 子文件夹

**详细规范**：需要时读取 `references/format-guide.md`

## 按需加载指引

- **完整协议**：`references/full-protocol.md` - 所有规范的完整版本
- **Commit 规范**：`references/commit-guide.md` - 生成 commit 信息时加载
- **调试规范**：`references/debug-guide.md` - 处理 Bug 时加载
- **macOS 版本规范**：`references/macos-version-guide.md` - 编写 macOS/Swift 代码时加载
- **工作流规范**：`references/workflow-guide.md` - 需要详细工作流时加载
- **格式规范**：`references/format-guide.md` - 需要格式说明时加载
- **版本发布规范**：`references/release-guide.md` - 准备发布新版本时加载

## 编译规范

**禁止通过命令行编译本项目**（如 `xcodebuild`）。代码修改完成后提醒用户在 Xcode 中打开 `ttsCopy.xcodeproj` 并手动编译运行（Cmd + R）。
