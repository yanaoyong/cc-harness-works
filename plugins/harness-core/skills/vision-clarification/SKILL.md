---
name: vision-clarification
description: 元流程 M0 愿景澄清。把模糊愿景澄清为可被下游消费的 vision.md。触发于 M0。
trigger_phase: M0
trigger: 元流程模式 A/D · 或模式 E REOPEN M0
inputs: 用户口述的项目目标 + 利益相关方信息
outputs: proj-*/m0_vision/vision_vN.md
version: 1.0.0
updated: 2026-06-12
spec: docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md
---

# Skill · 愿景澄清（vision-clarification）

## 1. 目的
把用户的"模糊愿景"澄清为**可被下游消费的项目目标声明**（要解决什么问题 / 不解决什么 / 成功标准 / 利益相关方），形成 `vision.md`，作为元流程 M1–M5 与 10 阶段 spec 的最上游契约源。

## 2. 触发条件
**元流程模式 A/D · 或模式 E REOPEN M0**（与 `08-Skills 扩展规范` §2 表 S1 行一致）：
- 模式 A（First-Run）：新项目启动时直接进入；
- 模式 D（Re-Vision）：方向重定位时重做；
- 模式 E：M0 PASSED 后被显式 REOPEN（**必填 `revise_reason`**，Q6.β-3；REOPEN 后由 Owner 触发级联评估 M1–M5 + 已上线 Roadmap 卡，HITL 拍板各下游 KEEP/REOPEN）。

## 3. 输入
- 用户口述的项目目标 + 利益相关方信息；
- 模式 E 时额外输入：既有已 PASSED 的 `vision.md`（修订基线）+ `revise_reason`。

## 4. 步骤（SOP）
1. **确认触发模式与版本基线**：模式 A/D 从 v1 起新建；模式 E 在既有版本上递增 vN，期间产出物 `status` 置 `REOPENED`（新版过 HITL 后回 `PASSED`）。
2. **五段对话采集**（与用户逐段澄清，任一段缺失不能 PASSED）：
   - ① **问题陈述**（要解决什么）：业务痛点 / 用户场景 / 当前无解的问题；
   - ② **不做声明**（不解决什么 · 必填）：明确排除范围，避免未来漂移；
   - ③ **成功标准**：可度量目标，**定量**（如 DAU > N / 错误率 < x%）与**定性**（如用户满意度）两类齐备；
   - ④ **利益相关方**：按"角色 / 关心什么 / 决策权重（高/中/低）"成表；
   - ⑤ **时间盒**（可选）：愿景的时效性边界，避免愿景僵化。
3. **形成 `vision_vN.md` 草稿**：写入 `../../changes/proj-<...>/m0_vision/vision_vN.md`，frontmatter 含 `version / updated / status`；正文结构与字段 schema **不在本 Skill 复制**，以 `02-M0 愿景澄清.md §3` 为权威。
4. **阶段独立性自检**（Q3 分次推进保证，见 02-M0 §4）：五段自封闭、面向业务利益相关方可读（不依赖工程上下文）、"默认假设"显式写出（如"假设并发量 < 100 RPS"）、PASSED 时填写 `pending_notes`（"M1 启动时应优先关注的 X 个问题"）。
5. **提交 Reviewer 评审**（≤3 轮）：评审机制以 `../expert-reviewer/SKILL.md`（现行版）为准，本 Skill 不复制其内部机制；评审 BLOCKED 时回到 M0 自身修订（modify-in-place，M0 为元流程起点、无前置回退）。
6. **HITL-M0 人工确认**：通过后 `status` 置 `PASSED`，并复制最新版到 `project/vision.md`。

## 5. 产出物
- `proj-*/m0_vision/vision_vN.md`（与 `08-Skills 扩展规范` §2 表 S1 行产出位置一致；运行时完整落点为 `../../changes/proj-<...>/m0_vision/vision_vN.md`，实例目录由元流程运行时创建）；
- PASSED 后复制最新版到 `project/vision.md`；
- 产出物五段结构与 frontmatter schema 权威：`02-M0 愿景澄清.md §3`（指针引用，不在此复制）。

## 6. 完成判据
- 五段（问题/不做/成功标准/利益相关方/时间盒）全部填写完整，无隐式默认假设；
- Reviewer 评审通过（`APPROVED`，或 `APPROVED_WITH_CONDITIONS` 经 Owner 核验条件闭合，见 `../../rules/开发流程规范.md` DF-002 注记；禁止按二态口径执行）；
- HITL-M0 通过，`pending_notes` 已填写。

## 7. 引用
- **执行者**：strategist 子 Agent（由 Owner 按元流程委派，见 `09-strategist 子 Agent` 设计 §2 角色矩阵）。
- 产出物 schema 权威：`docs/stage-02-全生命周期拓展/02-体系设计/02-M0 愿景澄清.md`（§3 结构 / §4 阶段独立性 / §5 模式 E 场景 / §6 下游契约）。
- 骨架与体例：`docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md` §2 / §3.1 / §5。
- 评审：`../expert-reviewer/SKILL.md`（现行版为准，仅指针引用）。
- 下游：`../requirement-elicitation/`（M1 消费 `vision.md §1 + §4`）；M2 消费 §3 成功标准；M3 消费 §3 定量指标；10 阶段 spec 消费 §2 不做声明（越界判断）。
