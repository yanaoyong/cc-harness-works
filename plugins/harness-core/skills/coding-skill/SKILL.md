---
name: coding-skill
trigger: 阶段3 编码实现
inputs: 已 APPROVED 的 spec.md / tasks.md
outputs: 代码、coding_report_vN.md
version: 1.1.0
updated: 2026-06-02
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: vendor-neutral（具体栈见 HARNESS_CONFIG.yaml）
---

# Skill · 编码实现（coding-skill）

## 1. 目的

按已批准的计划，遵循 `layeredSpecMapping()` 返回的 `SpecLayer[]`（本项目实值 = `coding-skill/specs/` 8 份后端分层 Spec · 分层语义见 `../../rules/工程结构.md` §2.1 ES）逐层实现，产出符合 Rules 的代码与编码报告。

## 2. 触发条件

进入 **阶段3**（阶段2 APPROVED 且 HITL-2 通过）时加载；**按当前所处层加载对应分层 Spec**（见 `specs/README.md`），不一次性全量加载。

## 3. 输入

- 已 APPROVED 的 `spec.md` / `tasks.md`；
- `../../rules/工程结构.md`、`../../rules/项目编码规范.md`；
- 既有代码（变更前先读懂，避免模仿错误 Pattern，如浮点存金额、外部 HTTP 调用无超时降级）。

## 4. 步骤（SOP）

> **起手批量并发首读（proposal-012 §3② · 一条消息并发）**：进入阶段3 第一动作 = 把以下独立首读项在**一条消息内并发**读取——`spec.md` + `tasks.md` + `../../rules/项目编码规范.md` + `../../rules/工程结构.md`；分层 Spec 与既有代码按当前所处层随后按需加载。
>
> **减肥刀法（proposal-012 §3⑤ · 压早期高复利沉积）**：① **编码前摸底外包**——优先派 Explore 子 Agent 或 `cg explore`、主循环只收摘要（**codegraph 未接入时降级为 Explore 子 Agent**）；② **Read 定点化**——用 `offset`/`limit` 或 `cg node` 读符号/片段，**不整文件 Read**；③ **内联脚本落盘复用**——heredoc 长脚本首跑即写 scratchpad 文件、后续只调路径，不在回合间反复内联重贴。

1. 阅读 spec/tasks，确认改动范围与分层归属（对照 `工程结构.md` §2.1）。
2. **逐层实现**：按 `layeredSpecMapping()` 返回的 `SpecLayer[]` 顺序逐层实现（本项目实值 = `coding-skill/specs/` 8 份后端分层 Spec · 分层顺序与语义见 `../../rules/工程结构.md` §2.1 ES）。
3. 全程遵守硬约束（见 `项目编码规范.md` §0 / §2 通用层 GEN）：
   - 金额用整数最小单位（分），禁浮点存金额（GEN-1 · 栈特定载体见 `项目编码规范.md §3 PY`）；
   - 外部 HTTP/RPC 调用须设超时 + 降级（GEN-2 · 栈特定载体见 `项目编码规范.md §3 PY-3`）；
   - 表现/编排层不写大段业务，委托业务层（GEN-4 · 栈特定载体见 `项目编码规范.md §3 PY`）。
4. 不做超出需求范围的重构；复用已有包（GEN-7）。
5. **构建验证**（在业务子项目根执行；对比测试 A 轮默认见 `HARNESS_CONFIG.yaml` `compare_path_a`）：执行绑定层栈无关的『依赖装配 + 构建/收集校验』步骤——即 `testCommand()` 给出的等价测试命令的构建/收集校验步骤（本项目实值见 `HARNESS_CONFIG.yaml` `test_command` 与 `../../rules/项目编码规范.md §3 PY`）。
6. 产出 `coding_report_vN.md`：改动点、分层对照、硬约束自检、风险。

## 5. 产出物

- 代码变更（对比测试 A 轮在 `HARNESS_CONFIG.yaml` `compare_path_a` 指向的业务子项目；其他以 spec 为准）；
- `../../changes/<变更目录>/coding/coding_report_vN.md`（版本递增）。

> 报告精简：本 SKILL 产出的报告类产物须满足 `../../rules/开发流程规范.md` **DF-012**（报告预算：内容硬约束 + 100 行软自检线 + 证据优先 + 不硬截断；`spec.md`/`tasks.md` 豁免）。

## 6. 完成判据

- **构建通过**：`testCommand()` 的构建/收集校验步骤无错误（本项目实值见 `HARNESS_CONFIG.yaml` `test_command`）；
- 对照分层 Spec / Rules 无 MUST 违反；
- 编码报告齐全，交付阶段 4 评审。

## 7. 引用

- 分层 Spec 索引：`specs/README.md`（8 份后端分层 Spec · 经 `layeredSpecMapping()` 抽象引用）
- 规则：`../../rules/项目编码规范.md`、`../../rules/工程结构.md`
- 下游：`../code-review/`、`../expert-reviewer/`（阶段4）
- 阶段与门禁：`docs/stage-01-Harness体系建设/02-体系设计/07-十阶段流程详细规范.md`、`docs/stage-01-Harness体系建设/03-质量与改进/08-质量门禁与反馈回路规范.md`
