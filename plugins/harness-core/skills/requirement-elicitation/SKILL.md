---
name: requirement-elicitation
description: 元流程 M1 需求挖掘。把 M0 愿景展开为需求池、用户故事与优先级初评 requirements.md。
trigger_phase: M1
trigger: M0 PASSED · 模式 B 直接进入 · 模式 E REOPEN M1
inputs: vision.md（M0 产物）+ 用户场景调研材料
outputs: proj-*/m1_requirements/requirements_vN.md
version: 1.0.0
updated: 2026-06-12
spec: docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md
---

# Skill · 需求挖掘（requirement-elicitation）

## 1. 目的
把 M0 愿景**展开**为可被下游消费的**需求池 + 用户故事 + 优先级初评**（`requirements.md`），确保 M2 圈定范围时有足够素材。M1 需求池不是一次性产物，是持续维护的池子（ad-hoc 卡影响较大时经模式 E 回流追加）。

## 2. 触发条件
**M0 PASSED · 模式 B 直接进入 · 模式 E REOPEN M1**（与 `08-Skills 扩展规范` §2 表 S2 行一致）：
- 模式 A：M0 PASSED 后进入；
- 模式 B（Module-Init）：直接进入（继承 M0 愿景）；
- 模式 D：M0 重做后进入；
- 模式 E：M1 被显式 REOPEN（**必填 `revise_reason`**，须有明确影响范围与修订理由，非无成本随意回写；典型来源为 Q8.2 ad-hoc 卡影响较大回流——新增 API / 新用户场景 / 业务规则变化）。

## 3. 输入
- `vision.md`（M0 产物，重点消费 §1 问题陈述 + §4 利益相关方）+ 用户场景调研材料；
- 模式 E 时额外输入：既有已 PASSED 的 `requirements.md` + `revise_reason`。

## 4. 步骤（SOP）
1. **对齐上游版本**：读取 `project/vision.md` 当前版本，产出物 frontmatter **必填 `upstream_vision_version`**（标记本 M1 版本对齐的 M0 版本；M0 后续 REOPEN 升版时，M1 触发模式 E 可据此对齐）。
2. **识别用户类型与场景**：从愿景 §1/§4 派生，按"用户类型 / 主要场景 / 价值描述"成表。
3. **写用户故事**：需求列表逐条用 "作为 <角色>，我想 <做什么>，以便 <价值>" 格式，编号 `R-XXX`（R-XXX 与 M5 的 RM-XXX 为独立编号空间、多对多映射，见 `07-M5 Roadmap 拆解.md §10` 已定结论）。
4. **初评价值 + 优先级**：每条需求标注价值评估（高/中/低）与优先级初评（P0/P1/P2/P3）。
5. **初列非功能需求（NFR）**：性能/可用性/安全/可扩展四类先占位，标"待 M3.2 量化"（QAS 详化在 M3.2）。
6. **登记已知约束**：法规/合规/技术债/历史接口兼容等不可妥协硬约束。
7. **列开放问题待 M2 拍板**：如"是否包含 X 功能 / 是否支持 Y 平台"，作为移交 M2 的明确清单。
8. **写入 `requirements_vN.md`**：落 `../../changes/proj-<...>/m1_requirements/requirements_vN.md`；五段结构与 frontmatter schema **不在本 Skill 复制**，以 `03-M1 需求池.md §3` 为权威。
9. **阶段独立性自检**（Q3，见 03-M1 §5）：五段自封闭、`upstream_vision_version` 已对齐、PASSED 时填 `pending_notes`（"M2 圈定时应优先讨论的 N 个开放问题"）。
10. **提交 Reviewer 评审**（≤3 轮）：以 `../expert-reviewer/SKILL.md`（现行版）为准，仅指针引用、不复制其内部机制；重大偏差（需求池暴露 M0 愿景本身不可行）→ 升级 Owner 显式 REOPEN M0（模式 E），不在 M1 内消化。
11. **HITL-M1 人工确认**：通过后 `status` 置 `PASSED`；按 `project/` 写入分层（`01-元流程总览.md §6.3`）写入——模式 B 写可多实例层 `project/requirements/<module>.md`（各模块独立文件不互相覆盖），聚合索引 `project/requirements.md` **不被直接覆盖**（由 Owner 按分层规则合并/索引）。

## 5. 产出物
- `proj-*/m1_requirements/requirements_vN.md`（与 `08-Skills 扩展规范` §2 表 S2 行产出位置一致；运行时完整落点为 `../../changes/proj-<...>/m1_requirements/requirements_vN.md`，实例目录由元流程运行时创建）；
- PASSED 后按 `project/` 写入分层落 `project/requirements/<module>.md` 等（见 SOP 第 11 步）；
- 产出物五段结构与 frontmatter schema 权威：`03-M1 需求池.md §3`（指针引用，不在此复制）。

## 6. 完成判据
- 五段（用户类型与场景 / 需求列表 / NFR / 已知约束 / 开放问题）齐全；
- `upstream_vision_version` 字段已对齐 M0 当前 PASSED 版本；
- Reviewer 评审通过（`APPROVED`，或 `APPROVED_WITH_CONDITIONS` 经 Owner 核验条件闭合，见 `../../rules/开发流程规范.md` DF-002 注记；禁止按二态口径执行）；
- HITL-M1 通过，`pending_notes` 已填写。

## 7. 引用
- **执行者**：strategist 子 Agent（由 Owner 按元流程委派，见 `09-strategist 子 Agent` 设计 §2 角色矩阵）。
- 产出物 schema 权威：`docs/stage-02-全生命周期拓展/02-体系设计/03-M1 需求池.md`（§3 结构 / §4 ad-hoc 回流 / §5 阶段独立性 / §6 下游契约）。
- 骨架与体例：`docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md` §2 / §3.2 / §5。
- 评审：`../expert-reviewer/SKILL.md`（现行版为准，仅指针引用）。
- 上游：`../vision-clarification/`（M0 产 `vision.md`）。下游：`../scope-framing/`（M2 消费 §2 需求列表 + §5 开放问题）；M3 消费 §3 NFR；M5 消费 §2 + §4。
