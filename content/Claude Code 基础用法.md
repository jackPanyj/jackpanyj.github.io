## 什么是 Claude Code

Claude Code 是 Anthropic 官方的 CLI 开发工具，在终端中与 Claude 交互，直接读写文件、执行命令、搜索代码、操作 Git。本文重点介绍代理配置和高级用法。

## 安装与代理配置

```bash
npm install -g @anthropic-ai/claude-code
```

### 代理设置

Claude Code 需要连接 Anthropic API，国内环境通常需要配置代理。在 `~/.claude/settings.json` 中设置：

```json
{
  "env": {
    "HTTPS_PROXY": "http://user:pass@proxy-host:port",
    "NO_PROXY": "localhost,127.0.0.1"
  }
}
```

也可以用环境变量：

```bash
export HTTPS_PROXY=http://user:pass@proxy-host:port
claude
```

`env` 里的变量会注入到 Claude Code 进程和它启动的所有子进程（包括 MCP Server），所以 MCP 的网络请求也会走这个代理。

`NO_PROXY` 用于排除不需要走代理的地址，比如本地开发服务器。

## 配置文件体系

Claude Code 有两层配置文件：

| 文件                              | 用途                  | 是否提交到 Git |
| ------------------------------- | ------------------- | --------- |
| `~/.claude/settings.json`       | 全局配置（权限、代理、hooks 等） | 否         |
| `~/.claude/settings.local.json` | 本地覆盖配置，优先级更高        | 否         |
| `~/.claude/CLAUDE.md`           | 全局提示词指令             | 否         |
| `项目/CLAUDE.md`                  | 项目级提示词指令            | 可以        |
| `~/.claude.json`                | MCP 配置 + 内部状态       | 否         |

`settings.json` 和 `settings.local.json` 会合并，`local` 优先。适合把通用权限放 `settings.json`，把临时/敏感的放 `settings.local.json`。

## 权限配置

### 权限模式

按 `Shift+Tab` 切换模式：

- **Ask** — 每次操作需确认（默认）
- **Auto** — 自动执行
- **Custom** — 白名单控制

### 白名单配置

在 `settings.json` 的 `permissions.allow` 中预授权操作，避免反复确认：

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Write",
      "Edit",
      "Bash(git *)",
      "Bash(pnpm *)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(node *)",
      "Bash(curl *)",
      "Bash(ls *)",
      "Bash(mkdir *)",
      "mcp__confluence__confluence_get_page",
      "WebFetch(domain:api.telegram.org)",
      "WebSearch"
    ]
  }
}
```

权限格式说明：

| 格式 | 含义 | 示例 |
|------|------|------|
| `"Read"` | 允许所有文件读取 | |
| `"Bash(git *)"` | 允许所有 git 命令 | `git status`, `git log` 等 |
| `"Bash(python3 scripts/build.py)"` | 精确匹配某条命令 | |
| `"mcp__<server>__<tool>"` | 允许某个 MCP 工具 | `mcp__confluence__confluence_get_page` |
| `"WebFetch(domain:xxx)"` | 允许访问特定域名 | `WebFetch(domain:api.telegram.org)` |
| `"Read(//path/**)"` | 限定路径的读取权限 | `Read(//Users/jack/**)` |

### Dangerously Skip Permissions

如果你完全信任 Claude 的操作（比如个人项目、本地开发），可以跳过所有权限确认：

```bash
# 启动时加 --dangerously-skip-permissions
claude --dangerously-skip-permissions
```

这个模式下 Claude 可以自由执行任何操作（读写文件、执行 shell 命令、MCP 调用等），不会弹出确认。

也可以在 `settings.json` 里关闭危险模式的二次确认弹窗：

```json
{
  "skipDangerousModePermissionPrompt": true
}
```

设了这个后，`--dangerously-skip-permissions` 启动时不会再弹"你确定吗"的警告。

> **注意**：这个模式适合个人开发环境。在共享机器或生产环境不要用，Claude 可能执行破坏性操作（rm、force push 等）。

### additionalDirectories

默认 Claude 只能访问当前工作目录。用 `additionalDirectories` 扩展访问范围：

```json
{
  "permissions": {
    "additionalDirectories": [
      "/tmp",
      "/Users/jack/other-project/src"
    ]
  }
}
```

## MCP Server 配置

MCP（Model Context Protocol）让 Claude 调用外部工具。配置在 `~/.claude.json` 中：

```json
{
  "mcpServers": {
    "confluence": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "confluence-mcp-server"],
      "env": {
        "CONF_BASE_URL": "http://your-confluence:8090",
        "CONF_USERNAME": "user",
        "CONF_PASSWORD": "pass"
      }
    }
  }
}
```

### 添加 MCP

```bash
# CLI 方式添加
claude mcp add -s user <name> -- <command> [args...]

# 示例
claude mcp add -s user confluence -- npx -y confluence-mcp-server

# 查看已配置
claude mcp list
```

### MCP 作用域

| 作用域 | 配置文件 | 场景 |
|--------|---------|------|
| `user` | `~/.claude.json` | 全局工具（Confluence、Jira、Linear 等） |
| `local` | `.claude/.mcp.json` | 项目私有工具，不提交 |
| `project` | `.mcp.json` | 项目共享工具，提交到仓库 |

### env 与代理的关系

MCP Server 的 `env` 字段设置的是该 MCP 进程的环境变量。同时 `settings.json` 里的全局 `env`（如 `HTTPS_PROXY`）也会传递给 MCP 进程。如果 MCP 需要走代理访问外部 API，全局代理配置即可生效。

## Hooks（钩子）

Hooks 在特定事件触发时自动执行 shell 命令：

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "terminal-notifier -title 'Claude Code' -message \"$(cat /dev/stdin | jq -r '.message')\" -sound Glass",
            "async": true
          }
        ]
      }
    ]
  }
}
```

### 可用事件

| 事件 | 触发时机 |
|------|---------|
| `PreToolUse` | 工具调用前 |
| `PostToolUse` | 工具调用后 |
| `Notification` | Claude 发出通知时 |
| `SessionStart` | 会话启动时 |
| `UserPromptSubmit` | 用户发送消息时 |

### matcher 过滤

可以用 `matcher` 只对特定工具生效：

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Bash command executed'"
          }
        ]
      }
    ]
  }
}
```

## Skills（技能）

Skills 是可复用的工作流模板，定义 Claude 完成某类任务的标准流程。

### 目录结构

```
~/.claude/skills/
├── weekly-report/
│   └── SKILL.md
├── review-mr/
│   └── SKILL.md
└── vue-setup-component/
    └── SKILL.md
```

### SKILL.md 格式

```markdown
---
name: weekly-report
description: "触发条件描述。Usage: /weekly-report [args]"
---

流程正文，定义步骤、规则、模板...
```

### 调用方式

```
/weekly-report
/review-mr http://gitlab.com/xxx/-/merge_requests/123
```

### 安装社区 Skills

```bash
# 通过 skills.sh 安装
claude skills install <skill-name>
```

## Plugins（插件）

Plugins 是 Skills 的升级版，可以包含多个 skills 和 subagent：

```json
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "claude-hud@claude-hud": true
  }
}
```

### 常用插件

| 插件 | 功能 |
|------|------|
| `superpowers` | TDD、调试、计划模式、代码审查等工作流 |
| `context7` | 查询库的最新文档 |
| `claude-hud` | 状态栏显示 token 用量、模型等信息 |
| `code-simplifier` | 自动简化和优化代码 |
| `claude-md-management` | CLAUDE.md 审计和维护 |

### 添加第三方插件市场

```json
{
  "extraKnownMarketplaces": {
    "claude-hud": {
      "source": {
        "source": "github",
        "repo": "jarrodwatts/claude-hud"
      }
    }
  }
}
```

## StatusLine（状态栏）

在终端底部显示实时信息（token 用量、模型、费用等）：

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash -c 'plugin_dir=$(ls -1d \"$HOME\"/.claude/plugins/cache/claude-hud/claude-hud/*/ | sort -V | tail -1); exec bun \"${plugin_dir}src/index.ts\"'"
  }
}
```

也可以用简单的自定义脚本，只要输出 JSON 格式即可。

## CLAUDE.md 项目配置

每个项目的 `CLAUDE.md` 告诉 Claude 项目的上下文和规范：

```markdown
## 项目说明
- Vue 2.7 + TypeScript，使用 <script setup>
- 包管理器: pnpm
- 代码注释用英文

## 构建 & 部署
- 开发: pnpm dev
- 构建: pnpm build
- 部署: python3 scripts/jenkins-build.py

## 规范
- 禁止自行 git commit/push，等用户指令
- 组件命名用 PascalCase
```

层级优先级：子目录 > 项目根 > 全局 `~/.claude/CLAUDE.md`

## 实用技巧

- **Effort Level**：`settings.json` 里设 `"effortLevel": "medium"` 控制思考深度，`low/medium/high`
- **skipDangerousModePermissionPrompt**：跳过危险模式确认弹窗
- **`claude --continue`**：继续上次对话
- **`/compact`**：上下文太长时压缩
- **图片输入**：直接粘贴截图或拖拽图片到终端
- **Prompt Queue**：一次输入多个任务排队执行
- **Git Worktree**：`/worktree` 在隔离环境中开发，不影响当前分支
