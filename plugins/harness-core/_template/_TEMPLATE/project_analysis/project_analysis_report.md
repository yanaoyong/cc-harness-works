# 项目分析报告 · project_analysis_report

> 由 `project-analysis` Skill 产出（按需，非阶段 1 固定序号）。
> 模板：`changes/_TEMPLATE/project_analysis/`；规范：`.harness/skills/project-analysis/SKILL.md`。

## 1. 分析范围与日期

| 项 | 值 |
|---|---|
| 分析根路径 | {{仓库根或子路径}} |
| 变更目录 | {{feat-xxx-YYYYMMDD}} |
| 分析日期 | {{YYYYMMDD}} |
| 分析人/Agent | {{角色}} |

## 2. 仓库概览

### 2.1 技术栈信号

| 线索文件 | 是否存在 | 推断栈（仅事实，不猜业务） |
|---|---|---|
| `pyproject.toml` / `requirements.txt` | {{是/否}} | {{如 Python}} |
| `pom.xml` / `build.gradle` | {{是/否}} | {{如 Java/Maven}} |
| `package.json` | {{是/否}} | {{如 Node}} |
| 其他 | {{路径}} | {{…}} |

### 2.2 顶层目录树（2–3 层）

```text
{{tree 或列表}}
```

## 3. 分层与目录映射表

> 对照 `rules/工程结构.md`（ES-001/002/003）。Python 业务仓默认 api → service → repository。

| 路径 | 推断分层 | 依据/备注 |
|---|---|---|
| {{path}} | {{表现/应用/业务/数据/适配/制品/其他}} | {{…}} |

### 疑似逆向依赖（仅列证据）

| 从 | 到 | 依据 |
|---|---|---|
| {{path}} | {{path}} | {{import/引用线索}} |

## 4. 关键入口与依赖线索

| 类型 | 路径 | 一句话职责 |
|---|---|---|
| 启动/主类 | {{}} | {{}} |
| API / router | {{}} | {{}} |
| 测试根目录 `tests/` | {{}} | {{}} |
| 构建/测试入口 | {{pytest / pip install -e .}} | {{}} |

## 5. Harness / 规范制品检查（带 Harness 的仓库必填）

| 检查项 | 路径 | 状态 | 备注 |
|---|---|---|---|
| L1 引导 | `CLAUDE.md` | {{✅/❌/N/A}} | |
| 编排中枢 | `.harness/agents/application-owner.md` | {{}} | |
| Rules 三件套 | `.harness/rules/` | {{}} | |
| Skills 权威 | `.harness/skills/<name>/SKILL.md` | {{}} | |
| Claude 桥接 | `.claude/skills/<name>/SKILL.md` | {{}} | 须为指针，非双份正文 |
| 变更模板 | `.harness/changes/_TEMPLATE/` | {{}} | |
| hooks | `.claude/settings.json` + `.claude/hooks/` | {{}} | |
| MCP | `.mcp.json` | {{}} | |

### Skills 桥接成对表（分析 myharness 时建议填满）

| Skill | `.harness/skills/` | `.claude/skills/` 桥接 |
|---|---|---|
| request-analysis | {{}} | {{}} |
| {{…}} | {{}} | {{}} |

## 6. 风险与建议（供 request-analysis / coding-skill 引用）

> **禁止**写未经验证的业务假设；每条须可追溯到路径或规则编号。

| # | 风险/建议 | 类型 | 追溯（路径/规则） |
|---|---|---|---|
| 1 | {{}} | 风险/建议 | {{ES-00x / 路径}} |

## 7. 附录：命令与工具

| 命令/工具 | 用途 |
|---|---|
| {{如 find / tree / git ls-files}} | {{}} |
| MCP filesystem/git | {{若使用}} |
