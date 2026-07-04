---
name: scope-framing
description: 元流程 M2 范围圈定。按触发模式收敛需求池为本轮范围 scope.md。
trigger_phase: M2
trigger: M1 PASSED · 模式 E REOPEN M2
inputs: requirements.md + 触发模式（A/B/C/D/E）
outputs: proj-*/m2_scope/scope_vN.md
version: 1.0.0
updated: 2026-06-12
spec: docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md
---

# Skill · 范围圈定（scope-framing）

## 1. 目的
把 M1 需求池**收敛**为本轮要做的进出范围（MVP/模块/本轮 · 按触发模式语义），产出 `scope.md`——元流程从"发散收集"转向"收敛执行"的关键节点，并保证粒度可被 M3 自顶向下设计。

## 2. 触发条件
**M1 PASSED · 模式 E REOPEN M2**（与 `08-Skills 扩展规范` §2 表 S3 行一致）：
- 模式 A/B/D：M1 PASSED 后进入 M2；
- 模式 C：**默认继承既有 M2 范围、不进入 M2**，除非架构演进暴露范围变化并经 HITL 触发模式 E REOPEN M2；
- 模式 E：仅在 M2 被显式 REOPEN 时进入（**必填 `revise_reason`**；典型场景：ad-hoc 卡影响较大回流追加条目 / 某需求 XL 太大需拆解 / M3 暴露某进范围需求技术不可行）。

## 3. 输入
- `requirements.md`（M1 产物，重点消费 §2 需求列表 + §5 开放问题）+ 触发模式（A/B/C/D/E）；
- 模式 E 时额外输入：既有已 PASSED 的 `scope.md` + `revise_reason`。

## 4. 步骤（SOP）
1. **根据触发模式选择产出物文件名**（M2 语义随模式变化，命名经 HITL 确认，见 `04-M2 范围圈定.md §3`）：模式 A（MVP 范围）`scope.md` / `mvp-scope.md`；模式 B（本模块范围）`module-<name>-scope.md`；模式 C（仅当触发范围修订时）`arch-<topic>-scope.md`；模式 D（v2.0 范围）`scope-v2.md`；模式 E 沿用原文件名 + 版本递增 vN。
2. **对齐上游版本**：frontmatter 必填 `trigger_mode` 与 `upstream_requirements_version`（对齐 M1 当前 PASSED 版本）。
3. **拍板 M1 开放问题并圈进范围**：逐条处理 `requirements.md §5` 开放问题；进范围条目按 "ID（S-XXX）/ 需求引用（R-XXX）/ 描述 / 验收标准 / T-shirt 估算（S/M/L/XL）" 成表。优先级收敛方法论（如 MoSCoW / RICE / Kano）由本 Skill 按项目语境选用并在产出物中注明，不强制单一方法。
4. **圈出范围**：明确不做的条目按 "ID（O-XXX）/ 需求引用 / 排除理由 / 后续处理（下一版 / 永不做 / 待定）" 成表，防漂移。
5. **写整体验收标准**：定量 + 定性两类齐备，且**可被自动化测试覆盖**（M3.2 QAS 量化的前置条件）。
6. **识别关键风险与缓解**：按"风险 / 概率 / 影响 / 缓解策略"成表（M3.1 据此做防御性设计）；登记假设与依赖。
7. **粒度自检（与 M3 的接口约束，见 04-M2 §5）**：进范围条目以 S/M/L 为主；**若为 XL，必须标记"待 M5 拆解"**（M2 允许少量 L/XL；≤L 的硬要求落在 M5 Roadmap 卡完成判据，见 `../roadmap-planning/`）；M3 启动后若发现粒度不足，走模式 E REOPEN M2，不允许在 M3 内偷偷扩范围。
8. **写入 `scope_vN.md`**：落 `../../changes/proj-<...>/m2_scope/scope_vN.md`；五段结构与 frontmatter schema **不在本 Skill 复制**，以 `04-M2 范围圈定.md §4` 为权威。
9. **提交 Reviewer 评审**（≤3 轮）：以 `../expert-reviewer/SKILL.md`（现行版）为准，仅指针引用、不复制其内部机制；范围争议（需求池无法收敛 / 缺关键需求）→ 升级 Owner REOPEN M1，不在 M2 内造需求。
10. **HITL-M2 人工确认**：通过后 `status` 置 `PASSED`；按 `project/` 写入分层（`01-元流程总览.md §6.3`）写入可多实例层 `project/scopes/<scope-id>.md`（模式 B/C 各产独立文件不互相覆盖），聚合索引 `project/scope.md` **不被所有模式直接覆盖**。

## 5. 产出物
- `proj-*/m2_scope/scope_vN.md`（与 `08-Skills 扩展规范` §2 表 S3 行产出位置一致；运行时完整落点为 `../../changes/proj-<...>/m2_scope/scope_vN.md`，实例目录由元流程运行时创建；具体文件名按 SOP 第 1 步模式语义选定）；
- PASSED 后按 `project/` 写入分层落 `project/scopes/<scope-id>.md` 等（见 SOP 第 10 步）；
- 产出物五段结构与 frontmatter schema 权威：`04-M2 范围圈定.md §4`（指针引用，不在此复制）。

## 6. 完成判据
- M2 范围项**若为 XL，必须标记"待 M5 拆解"**（M2 阶段允许少量 L/XL · ≤L 的硬要求落在 M5 Roadmap 卡完成判据 · 见 `../roadmap-planning/`）；
- 整体验收标准可被自动化测试覆盖；关键风险已识别；
- 五段（进范围/出范围/整体验收/风险/假设依赖）齐全，`trigger_mode` 与 `upstream_requirements_version` 已填；
- Reviewer 评审通过（`APPROVED`，或 `APPROVED_WITH_CONDITIONS` 经 Owner 核验条件闭合，见 `../../rules/开发流程规范.md` DF-002 注记；禁止按二态口径执行）；
- HITL-M2 通过，`pending_notes` 已填写。

## 7. 引用
- **执行者**：strategist 子 Agent（由 Owner 按元流程委派，见 `09-strategist 子 Agent` 设计 §2 角色矩阵）。
- 产出物 schema 权威：`docs/stage-02-全生命周期拓展/02-体系设计/04-M2 范围圈定.md`（§3 模式语义 / §4 结构 / §5 与 M3 接口 / §6 模式 E 场景 / §7 下游契约）。
- 骨架与体例：`docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md` §2 / §3.3 / §5。
- 评审：`../expert-reviewer/SKILL.md`（现行版为准，仅指针引用）。
- 上游：`../requirement-elicitation/`（M1 产 `requirements.md`）。下游：`../architecture-design/`（M3 消费 §1 进范围 + §3 验收 + §4 风险）；`../roadmap-planning/`（M5 消费 §1 做 1:N 拆卡）；10 阶段 spec 消费 §3 验收标准。
