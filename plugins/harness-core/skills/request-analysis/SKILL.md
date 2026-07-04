---
name: request-analysis
trigger: 阶段1 需求分析
inputs: 用户需求描述、相关 Wiki/历史变更
outputs: spec.md、tasks.md
version: 1.0.0
updated: 2026-05-31
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
---

# Skill · 需求分析（request-analysis）

## 1. 目的
把用户原始需求转化为结构化的需求规格（spec）与可执行的任务拆分（tasks），为后续评审与编码奠定基线。

## 2. 触发条件
进入 **阶段1**（收到需求）时由编排中枢加载。

## 3. 输入
- 用户需求描述；
- 必要时按需查阅 `wiki/`（领域上下文）与历史 `.harness/changes/`（同类需求）。

## 4. 步骤（SOP）
1. 澄清需求意图与边界；存在歧义 → 在 **HITL-1** 升级人工确认，**不臆测**。
2. 梳理影响面（涉及模块/链路/接口/数据），引用 `../../rules/工程结构.md` 判断分层归属。
3. 产出 `spec.md`：背景、范围（含不做的事）、验收标准、影响面、风险。
4. 拆分 `tasks.md`：每个子任务明确 目标 / 范围 / 输入输出 / 验收标准 / 依赖。
5. 自检完整性后交付阶段2 评审。

## 5. 产出物
- `../../changes/<变更目录>/request_analysis/spec.md`
- `../../changes/<变更目录>/request_analysis/tasks.md`
（模板见 `docs/stage-01-Harness体系建设/03-质量与改进/09-变更管理与持久化记忆规范.md` / `../../_template/_TEMPLATE/`）

## 6. 完成判据
- `spec.md` 与 `tasks.md` 均存在且含必填章节；
- 无未决歧义标记（或已在 HITL-1 关闭）；
- 每个子任务具备可验证的验收标准。

## 7. 引用
- 规则：`../../rules/工程结构.md`、`../../rules/项目编码规范.md`
- 下游：`../expert-reviewer/`（阶段2 计划评审）
- 阶段与门禁：`docs/stage-01-Harness体系建设/02-体系设计/07-十阶段流程详细规范.md`、`docs/stage-01-Harness体系建设/03-质量与改进/08-质量门禁与反馈回路规范.md`
