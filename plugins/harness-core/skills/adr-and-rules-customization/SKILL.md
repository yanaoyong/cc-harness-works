---
name: adr-and-rules-customization
description: 元流程 M3.3 决策固化。沉淀 ADR 并派生定制 Rules（含 API 设计规范）。
trigger_phase: M3.3
trigger: M3.2 PASSED · 模式 E REOPEN M3（修订起点为 M3.3）
inputs: M3.1 + M3.2 全部产出
outputs: proj-*/m3_architecture/m3.3_customization/ 下 ADR 集合 + 4+ 份定制 Rules
version: 1.0.0
updated: 2026-06-12
spec: docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md
---

# Skill · 决策固化与定制 Rules（adr-and-rules-customization · M3.3）

## 1. 目的
把 M3.1/M3.2 的架构决策**固化为 ADR 集合**（视图④）并**派生项目定制 Rules**（视图⑧，覆盖 stage-01 模板，含 `API 设计规范.md`）。M3.3 是 M3 三子阶段的收口段，其定制 Rules 是 M4 工程基线覆盖 `.harness/rules/` 的直接上游。

## 2. 触发条件
- **M3.2 PASSED · 模式 E REOPEN M3（修订起点为 M3.3）**（08 §2 表 S6 行）。
- 进入条件（五要素）：M3.2 PASSED（05-M3 §5.1）。
- 连贯跑约束：与 M3.1 / M3.2 在同一 M3 推进批次内连续执行，子阶段边界不作为可长期暂停/恢复边界（05-M3 §2）。
- 模式 E REOPEN 时 `revise_reason` 必填；改某 ADR 的口径 = 新增 ADR-NNN（头部 `supersedes: <旧 ADR>`），旧 ADR 标 `status: SUPERSEDED` + `superseded_by: ADR-NNN`，**旧 ADR 永不删**（05-M3 §6）。

## 3. 输入
- M3.1 全部产出（`proj-*/m3_architecture/m3.1_system/`，视图①②）；
- M3.2 全部产出（`proj-*/m3_architecture/m3.2_interface/`，视图③⑤⑥⑦，其中接口契约是定制 Rules 派生的直接输入）。

## 4. 步骤（SOP）
以 08 §3.6 骨架为纲、按 05-M3 §5（视图④ §5.2 + 视图⑧ §5.3）详化：
1. **识别关键二选一决策**：从 M3.1 结构选择（如部署形态）与 M3.2 契约/数据选择（如持久化选型、认证方案）中提取每一个"选了 A 就排除 B"的决策点。
2. **每决策写一份 ADR**（视图④）：背景 / 选项（各选项优劣）/ 决策 / 后果（正面+负面）/ 状态（`status` 与 `superseded_by` 拆字段口径），字段与示例**以 05-M3 §5.2 为权威**（其注明的 P4 权威模板指针一并沿用），本文不复制模板。
3. **基于 ADR + M3.2 接口契约派生定制 Rules**（视图⑧，05-M3 §5.3）：
   - `架构规范.md`（分层依赖 · 模块边界 · 通信协议，基于 C4 容器图）；
   - `工程结构.md`（定制版，覆盖 stage-01 模板，反映本项目实际目录结构）；
   - `项目编码规范.md`（定制版，覆盖 stage-01 模板，含本项目命名/类型/异常约定）;
   - **`API 设计规范.md`**（内容详化指针：`docs/stage-02-全生命周期拓展/03-质量与改进/03-API 设计规范.md`）；
   - 其他按需（如 `数据访问规范.md` / `日志规范.md`）。
   定制 Rules 的**落地覆盖机制**仅指针引用同目录 `10-定制 Rules 沉淀与覆盖机制.md`，本 Skill 不展开复制（实际覆盖动作发生在 M4，由 `engineering-baseline` 执行）。
4. **自检并提交质量门禁**：HITL-M3.3 + Reviewer 评审 + **Rules 定型确认**（≤2 轮）。失败回退：ADR 沉淀过程暴露根本性架构问题 → 升级 Owner 触发 REOPEN M3.1（05-M3 §5.1 五要素表）。

## 5. 产出物
- 运行时落点：`.harness/changes/proj-<...>/m3_architecture/m3.3_customization/`（08 §2 表 S6 行「产出位置」列；实例目录由元流程运行时产生，本 Skill 文件不预创建）。
- 两类文档：**ADR 集合**（视图④）+ **4+ 份定制 Rules**（视图⑧）；清单与 schema **以 05-M3 §5 为权威**，覆盖机制以 `10-定制 Rules 沉淀与覆盖机制.md` 为权威，本文均不复制细节。

## 6. 完成判据
- ADR 至少 1 条（字段齐全，符合 05-M3 §5.2 拆字段口径）；
- 定制 Rules 至少含 `API 设计规范.md`；
- Reviewer 评审通过（`APPROVED`，或 `APPROVED_WITH_CONDITIONS` 经 Owner 核验条件闭合，见 `.harness/rules/开发流程规范.md` DF-002 注记）——评审执行仅指针引用 `../expert-reviewer/SKILL.md`（现行版为准）；
- HITL-M3.3 通过 + **Rules 定型确认**通过；
- 评审 ≤2 轮；任一子阶段超过 2 轮、或 M3 累计返工超过 3 次 → 升级人工决策（05-M3 §2 循环上限）。

## 7. 引用
- 产出物 schema 权威：`docs/stage-02-全生命周期拓展/02-体系设计/05-M3 架构设计（三子阶段详化 · 8 类视图）.md` §5（五要素表 §5.1、视图④ §5.2、视图⑧ §5.3、REOPEN 与 ADR 演进 §6）。
- 骨架与清单：同目录 `08-Skills 扩展规范（含 fe-integration）.md` §2 表 S6 行 + §3.6。
- 定制 Rules 覆盖机制：同目录 `10-定制 Rules 沉淀与覆盖机制.md`（仅指针引用，不展开复制）；API 设计规范内容：`docs/stage-02-全生命周期拓展/03-质量与改进/03-API 设计规范.md`。
- 评审：`../expert-reviewer/SKILL.md`（仅指针引用，不复制其内部机制）；三态口径见 `../../rules/开发流程规范.md` DF-002 注记。
- 上游：`../interface-design/`（M3.2）；下游：`../engineering-baseline/`（M4，消费定制 Rules 执行 `.harness/rules/` 覆盖）、10 阶段评审强绑定（05-M3 §7）。
- **执行者**：strategist 子 Agent（定义见 `.claude/agents/strategist.md`，与 `docs/stage-02-全生命周期拓展/02-体系设计/09-strategist 子 Agent 定义.md` §2 角色矩阵一致）。
