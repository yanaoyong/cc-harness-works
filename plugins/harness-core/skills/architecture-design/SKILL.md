---
name: architecture-design
description: 元流程 M3.1 系统架构设计。产出 C4 系统架构视图 + 领域模型视图（DDD+ER）。
trigger_phase: M3.1
trigger: M2 PASSED · 模式 C 直接进入 M3.1 · 模式 E REOPEN M3（修订起点为 M3.1）
inputs: scope.md（M2 产物）、M0 愿景（vision.md）
outputs: proj-*/m3_architecture/m3.1_system/ 下视图①②文档集
version: 1.0.0
updated: 2026-06-12
spec: docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md
---

# Skill · 系统架构设计（architecture-design · M3.1）

## 1. 目的
把 M2 圈定的范围自顶向下设计为可工程化执行的架构起点：产出**系统架构视图（C4）**与**领域模型视图（DDD+ER）**（M3 八类视图中的视图①②）。M3.1 是元流程 M3 三子阶段的第一段，为 M3.2 接口设计与 M3.3 决策固化提供结构基底。

## 2. 触发条件
- **M2 PASSED · 模式 C 直接进入 M3.1 · 模式 E REOPEN M3（修订起点为 M3.1）**（08 §2 表 S4 行）。
- 进入条件（五要素）：M2 PASSED——`scope.md` §1 进范围 + §3 验收 + §4 风险已齐备（05-M3 §3.1）。
- 连贯跑约束：M3.1 / M3.2 / M3.3 在**同一 M3 推进批次内连续执行**，子阶段边界不作为可长期暂停/恢复边界（05-M3 §2）。
- 模式 E REOPEN 时 `revise_reason` 必填，级联评估口径见 05-M3 §6（改 C4 容器图会高概率级联建议 REOPEN M3.2/M3.3）。

## 3. 输入
- `scope.md`（M2 产物，运行时位于 `proj-*/m2_scope/`）；
- M0 愿景 `vision.md`（运行时位于 `proj-*/m0_vision/`）。

## 4. 步骤（SOP）
以 08 §3.4 骨架为纲、按 05-M3 §3（§3.2 视图① + §3.3 视图②）详化：
1. **画 C1 上下文图**：系统 + 外部用户 + 外部系统 → `c4-context.md`（mermaid / PlantUML / 文本描述均可）。
2. **画 C2 容器图**：系统内主要可独立部署单元（API / DB / 缓存 / MQ）→ `c4-container.md`。
3. **画部署拓扑**：容器映射到运行环境（单机 / K8s / 云）→ `deployment-topology.md`。C4 组件图/代码图通常太细，可省略到目标项目 M4 工程基线阶段再画（可选项）。
4. **识别限界上下文**（Bounded Context）→ `domain-bounded-contexts.md`。
5. **画聚合根 + ER**：聚合根 + 实体 + 值对象 → `domain-aggregates.md`；实体关系（ER 图）→ `domain-er.md`（mermaid 或文本）。
6. **自检并提交质量门禁**：HITL-M3.1 + Reviewer 评审（≤2 轮）。失败回退：领域建模与愿景脱节 → 升级 Owner 触发模式 E REOPEN M0/M1（05-M3 §3.1 五要素表）。

## 5. 产出物
- 运行时落点：`.harness/changes/proj-<...>/m3_architecture/m3.1_system/`（08 §2 表 S4 行「产出位置」列；实例目录由元流程运行时产生，本 Skill 文件不预创建）。
- 文档清单与各文档 schema **以 05-M3 §3 为权威**（视图①：`c4-context.md` / `c4-container.md` / `deployment-topology.md`；视图②：`domain-bounded-contexts.md` / `domain-aggregates.md` / `domain-er.md`），本文不复制 schema 细节。

## 6. 完成判据
- 视图①②文档齐全（清单以 05-M3 §3 为权威核对）；
- Reviewer 评审通过（`APPROVED`，或 `APPROVED_WITH_CONDITIONS` 经 Owner 核验条件闭合，见 `.harness/rules/开发流程规范.md` DF-002 注记）——评审执行仅指针引用 `../expert-reviewer/SKILL.md`（现行版为准）；
- HITL-M3.1 通过；
- 评审 ≤2 轮；任一子阶段超过 2 轮、或 M3 累计返工超过 3 次 → 升级人工决策（05-M3 §2 循环上限）。

## 7. 引用
- 产出物 schema 权威：`docs/stage-02-全生命周期拓展/02-体系设计/05-M3 架构设计（三子阶段详化 · 8 类视图）.md` §3（五要素表 §3.1、视图①② §3.2–§3.3、REOPEN 特殊性 §6）。
- 骨架与清单：同目录 `08-Skills 扩展规范（含 fe-integration）.md` §2 表 S4 行 + §3.4。
- 评审：`../expert-reviewer/SKILL.md`（仅指针引用，不复制其内部机制）；三态口径见 `../../rules/开发流程规范.md` DF-002 注记。
- 下游：`../interface-design/`（M3.2，消费本子阶段全部产出）。
- **执行者**：strategist 子 Agent（定义见 `.claude/agents/strategist.md`，与 `docs/stage-02-全生命周期拓展/02-体系设计/09-strategist 子 Agent 定义.md` §2 角色矩阵一致）。
