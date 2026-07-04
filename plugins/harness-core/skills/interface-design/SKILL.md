---
name: interface-design
description: 元流程 M3.2 接口设计。产出接口契约 + QAS + 横切关注点 + 数据架构。
trigger_phase: M3.2
trigger: M3.1 PASSED · 模式 E REOPEN M3（修订起点为 M3.2）
inputs: M3.1 全部产出、M1 NFR、M0 定量目标
outputs: proj-*/m3_architecture/m3.2_interface/ 下视图③⑤⑥⑦文档集（8+ 份）
version: 1.0.0
updated: 2026-06-12
spec: docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md
---

# Skill · 接口设计（interface-design · M3.2）

## 1. 目的
在 M3.1 结构基底之上产出**接口契约视图（API + 事件）**、**质量属性场景（QAS）**、**横切关注点**与**数据架构**（M3 八类视图中的视图③⑤⑥⑦），把架构从"结构"推进到"契约与质量可度量"，为 M3.3 决策固化与 10 阶段 spec「消费方契约」段提供上游来源。

## 2. 触发条件
- **M3.1 PASSED · 模式 E REOPEN M3（修订起点为 M3.2）**（08 §2 表 S5 行）。
- 进入条件（五要素）：M3.1 PASSED（05-M3 §4.1）。
- 连贯跑约束：与 M3.1 / M3.3 在同一 M3 推进批次内连续执行，子阶段边界不作为可长期暂停/恢复边界（05-M3 §2）。
- 模式 E REOPEN 时 `revise_reason` 必填；改 API 契约的级联评估建议 REOPEN M3.3（定制 Rules 可能受影响，05-M3 §6）。

## 3. 输入
- M3.1 全部产出（`proj-*/m3_architecture/m3.1_system/`，视图①②）；
- M1 NFR（`requirements.md` 中非功能需求项）；
- M0 定量目标（vision.md 定量成功标准，参考 `02-M0 §6 与下游的契约`）。

## 4. 步骤（SOP）
以 08 §3.5 骨架为纲、按 05-M3 §4（视图③⑤⑥⑦各节）详化：
1. **设计 API**（REST/GraphQL/RPC）→ `api-design.md` + 草稿 OpenAPI yaml；如有消息队列，写事件契约 → `event-contracts.md`（视图③，05-M3 §4.2）。该视图落到 M3.3 后被定制 Rules 化为 `API 设计规范.md`。
2. **量化 QAS**：性能 / 可用性 / 安全 / 可扩展四类**可度量目标**（视图⑤，05-M3 §4.3；输入 = M0 愿景的定量成功标准），逐条写成可验证表述（示例体例见 05-M3 §4.3）。
3. **设计横切关注点**（视图⑥，05-M3 §4.4）：认证授权模型 → `cross-cutting-auth.md`；日志/指标/追踪 → `cross-cutting-observability.md`；错误处理与降级 → `cross-cutting-error.md`；并发与一致性模型 → `cross-cutting-concurrency.md`。
4. **确定数据架构选型**（视图⑦，05-M3 §4.5）：持久化选型 → `data-storage-choice.md`（+ 对应 ADR，ADR 正文在 M3.3 落档）；数据生命周期 → `data-lifecycle.md`；备份恢复策略 → `data-backup.md`。
5. **自检并提交质量门禁**：HITL-M3.2 + Reviewer 评审（≤2 轮）。失败回退：接口契约与范围不符 → 升级 Owner 触发模式 E REOPEN M2（05-M3 §4.1 五要素表）。

## 5. 产出物
- 运行时落点：`.harness/changes/proj-<...>/m3_architecture/m3.2_interface/`（08 §2 表 S5 行「产出位置」列；实例目录由元流程运行时产生，本 Skill 文件不预创建）。
- 视图③⑤⑥⑦共 8+ 份文档；文档清单与 schema **以 05-M3 §4 为权威**，本文不复制 schema 细节。

## 6. 完成判据
- 视图③⑤⑥⑦ 4 类视图齐全（清单以 05-M3 §4 为权威核对）；
- OpenAPI 草稿可被 schemathesis 解析；
- QAS 全部可度量（无不可验证的定性表述）；
- Reviewer 评审通过（`APPROVED`，或 `APPROVED_WITH_CONDITIONS` 经 Owner 核验条件闭合，见 `.harness/rules/开发流程规范.md` DF-002 注记）——评审执行仅指针引用 `../expert-reviewer/SKILL.md`（现行版为准）；
- HITL-M3.2 通过；
- 评审 ≤2 轮；任一子阶段超过 2 轮、或 M3 累计返工超过 3 次 → 升级人工决策（05-M3 §2 循环上限）。

## 7. 引用
- 产出物 schema 权威：`docs/stage-02-全生命周期拓展/02-体系设计/05-M3 架构设计（三子阶段详化 · 8 类视图）.md` §4（五要素表 §4.1、视图③ §4.2、视图⑤ §4.3、视图⑥ §4.4、视图⑦ §4.5、REOPEN 特殊性 §6）。
- 骨架与清单：同目录 `08-Skills 扩展规范（含 fe-integration）.md` §2 表 S5 行 + §3.5。
- 评审：`../expert-reviewer/SKILL.md`（仅指针引用，不复制其内部机制）；三态口径见 `../../rules/开发流程规范.md` DF-002 注记。
- 上游：`../architecture-design/`（M3.1）；下游：`../adr-and-rules-customization/`（M3.3，消费视图③定制 Rules 化）、10 阶段 spec「消费方契约」段与单测 QAS 基线（05-M3 §7）。
- **执行者**：strategist 子 Agent（定义见 `.claude/agents/strategist.md`，与 `docs/stage-02-全生命周期拓展/02-体系设计/09-strategist 子 Agent 定义.md` §2 角色矩阵一致）。
