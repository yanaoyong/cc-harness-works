---
name: project-analysis
description: 对目标仓库进行可验证的结构、分层与依赖方向摸底
trigger: 按需（阶段1 之前或并行；Owner 判定需要结构摸底时）
inputs: 仓库根目录、工程结构规则、可选 Wiki/历史变更
outputs: project_analysis_report.md（可选 module_map.md）
version: 1.1.0
updated: 2026-06-02
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
---

# Skill · 项目结构分析（project-analysis）

## 1. 目的

在需求分析或编码前，对目标仓库做**可验证的结构摸底**：目录与分层、关键入口、依赖方向、技术栈信号、与 Rules 的对照点，为 `request-analysis` / `coding-skill` 提供事实基线，减少臆测。

## 2. 触发条件

由编排中枢 **按需加载**（非 10 阶段固定序号），典型场景：

| 场景 | 说明 |
|---|---|
| 首次接入仓库 / 存量改造 | 进入阶段 1 前，结构未知 |
| 需求影响面跨多模块 | spec 写「影响面」前需目录级证据 |
| 对比测试 / Dry Run 前 | 确认制品布局与桥接是否齐全 |
| Owner 显式指令 | 「先做一次项目分析」 |

**边界**：

- **不替代**阶段 1：本 Skill 只产出分析报告，**不**产出 `spec.md` / `tasks.md`（仍由 `request-analysis` 负责）。
- **不**做编码、评审结论、CI/部署；发现的问题写入报告 §6，由后续阶段处理。

## 3. 输入

- 仓库根目录（`git status`、顶层目录树、构建/依赖描述文件若存在）；
- `../../rules/工程结构.md`（分层与依赖方向 ES-001~006）；
- 可选：`wiki/`、`.harness/changes/` 历史同类变更；
- 可选：MCP `filesystem` / `git`（根目录 `.mcp.json`）；
- 落盘模板：`../../_template/_TEMPLATE/project_analysis/`。

## 4. 步骤（SOP）

> **起手批量并发首读（proposal-012 §3② · 一条消息并发）**：进入摸底第一动作 = 把以下独立首读项在**一条消息内并发**执行——`git status` + 顶层目录树（`ls`/tree 2–3 层）+ 各栈依赖/构建声明文件 + `../../rules/工程结构.md`；不逐个串行采集。
>
> **减肥刀法 · 摸底外包（proposal-012 §3⑤）**：结构摸底优先派 **Explore 子 Agent** 或 **`cg explore`** 一次拿源码 + 关系 + 爆炸半径，**主循环只收摘要**、不把整仓 Read 进主上下文；**codegraph 未接入时降级为 Explore 子 Agent**（读代码类摸底不占主循环 token）。

1. **划定分析范围**：确认分析根路径（默认仓库根； monorepo 子项目则写明子路径与原因）。
2. **采集结构事实**（只陈述可核对事实，不猜测业务含义）：
   - 顶层目录树（2–3 层）；
   - 构建/依赖线索（各栈依赖/构建清单文件：依赖声明文件 / 锁文件 / 构建配置，存在则列路径）；
   - 若目标仓含 Harness：`.harness/`、`CLAUDE.md`、`.claude/` 是否成对存在。
3. **分层映射**：对照 `工程结构.md`，为一级源码/业务目录填「推断分层」；列出**疑似逆向依赖**（路径 + import/引用依据，不给重构方案）。
4. **关键入口清单**：入口模块 / app 工厂、路由层入口、测试根目录、构建/测试命令（按检测到的栈，路径 + 一句话）。
5. **Harness 专项检查**（分析 myharness 或已接入 Harness 的仓时**必填** §5）：
   - 核对 L1/L2 制品与 `docs/_meta-跨阶段/00-全项目制品总览.md` 索引是否一致；
   - 列出每个 Skill 的 `.harness/skills/<name>/` 与 `.claude/skills/<name>/` 桥接是否成对（桥接须为指针，见 `docs/stage-01-Harness体系建设/04-运行手册/12-运行时集成-ClaudeCode桥接规范.md`）。
6. **风险与建议**：每条关联路径或规则编号（如 ES-002）；供阶段 1 写入 spec「影响面/风险」时引用。
7. **落盘**到当前变更目录 `project_analysis/`，通知 Owner：可进入或回到阶段 1。

### 4.1 分析 myharness 模板仓时的快速检查表

| # | 检查项 | 期望 |
|---|---|---|
| H1 | `CLAUDE.md` @导入 Owner + Rules | 存在 |
| H2 | `skills/README.md` 与 `docs/_meta-跨阶段/00-全项目制品总览.md` 状态一致 | 无长期 ⏳ 与事实矛盾 |
| H3 | 流程 Skill 7 个 + 桥接 7 个 | 见 `skills/README.md` |
| H4 | `changes/_TEMPLATE/project_analysis/` | 报告模板存在 |
| H5 | hooks 三事件 | `PreToolUse`/`PostToolUse`/`Stop` |

## 5. 产出物

| 文件 | 路径 | 必填 |
|---|---|---|
| 项目分析报告 | `../../changes/<变更目录>/project_analysis/project_analysis_report.md` | 是 |
| 模块路径速查 | `../../changes/<变更目录>/project_analysis/module_map.md` | 否（多模块仓建议填） |

复制起点：`../../_template/_TEMPLATE/project_analysis/project_analysis_report.md`。

### `project_analysis_report.md` 必填章节

1. 分析范围与日期  
2. 仓库概览（技术栈信号、顶层树）  
3. 分层与目录映射表  
4. 关键入口与依赖线索  
5. Harness / 规范制品检查结果（无 Harness 的纯业务仓填 N/A 并说明）  
6. 风险与建议（供 request-analysis 引用，**不含**未经验证的业务假设）  
7. 附录：使用的命令/工具（便于复核）

## 6. 完成判据

- `project_analysis_report.md` 存在且上述 **7 个章节**齐全；
- 分层映射表至少覆盖分析范围内**所有一级业务/源码目录**（无源码则覆盖一级制品目录）；
- 每条「风险/建议」可追溯到具体路径或规则条目（如 ES-001）；
- 未将分析报告当作 spec（报告中**无**替代性验收标准整表、**无**任务拆分 T1/T2）；
- 分析 Harness 仓时：§5 含 Skills 桥接成对表，且已区分「权威正文 vs 桥接指针」。

## 7. 引用

- 规则：`../../rules/工程结构.md`、`../../rules/开发流程规范.md`
- 下游：`../request-analysis/`（阶段 1）、`../coding-skill/`（阶段 3，需分层 Spec 时）
- 变更落盘：`docs/stage-01-Harness体系建设/03-质量与改进/09-变更管理与持久化记忆规范.md`、模板 `../../_template/_TEMPLATE/project_analysis/`
- 阶段与门禁：`docs/stage-01-Harness体系建设/02-体系设计/07-十阶段流程详细规范.md`、`docs/stage-01-Harness体系建设/03-质量与改进/08-质量门禁与反馈回路规范.md`
- 桥接：`docs/stage-01-Harness体系建设/04-运行手册/12-运行时集成-ClaudeCode桥接规范.md`、`.claude/skills/project-analysis/SKILL.md`（指针）
- MCP：`.harness/mcp/README.md`、根目录 `.mcp.json`
