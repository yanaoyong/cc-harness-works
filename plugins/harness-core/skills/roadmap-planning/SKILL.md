---
name: roadmap-planning
description: 元流程 M5 Roadmap 拆解。把范围/架构/基线拆解为可独立交付的 Roadmap 卡。
trigger_phase: M5
trigger: M4 PASSED · 模式 E REOPEN M5
inputs: M2/M3/M4 全部产出
outputs: proj-*/m5_roadmap/ + 实际落 project/roadmap.md
version: 1.1.0
updated: 2026-06-19
spec: docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md
---

# Skill · Roadmap 拆解（roadmap-planning）

## 1. 目的
把 M2 范围 + M3 架构 + M4 基线**拆解为可独立交付的 Roadmap 卡片**，每张卡能 1:1 映射到一次 10 阶段流水线。M5 是元流程的终点、也是 10 阶段循环的起点：M5 PASSED 后元流程进入维护态，业务开发主战场切到 10 阶段。

## 2. 触发条件
- **M4 PASSED**（工程基线就绪 · 项目骨架可运行）→ 进入 M5；
- **模式 E REOPEN M5**（预期维护路径：ad-hoc 卡回流追加、XL 卡拆分、优先级重排、卡方案替换等，典型场景见图纸 `07-M5 Roadmap 拆解.md` §7；仍需 `revise_reason` 必填 + HITL 确认，涉及已启动/已完成卡时必须触发级联评估 Q6.β-2）。

由编排中枢（Application Owner）在元流程 M5 阶段委派 strategist 子 Agent 加载执行。

## 3. 输入
- M2 产出：`scope.md`（进范围条目，XL 项已标「待 M5 拆解」）；
- M3 产出：架构视图 / 接口契约 / ADR 与 `API 设计规范.md`（卡「技术备注」上游来源）；
- M4 产出：`project/tech-stack.md`（已确认技术栈）；
- 触发为模式 E REOPEN M5 时：`revise_reason` 与触发来源（如 ad-hoc 卡目录、待拆分的 XL 卡 ID）。

## 4. 步骤（SOP）
1. **按 M2 进范围 1:N 拆卡**：每条进范围条目拆为 1 至 N 张可独立交付的卡；M2 标「待 M5 拆解」的 XL 项必须在此拆为 T-shirt ≤ L 的卡。
2. **每卡 11 字段填写**：标题 / 描述 / 优先级 / 估算（T-shirt）/ 状态 / 验收标准（从 M2 scope.md 引用或细化）/ 技术备注（从 M3 ADR 与 API 设计引用）/ change_dir（10 阶段启动后由 Owner 自动追加，初始留空）/ dependencies / source（roadmap 或 ad-hoc-converted）/ created+updated 日期——字段 schema 权威见图纸 `07-M5` §3，本 SOP 不复制。
3. **确认模块落地验收闭环卡（条件式必出）**：若本步拆出的交付卡**落地了可被人 / 主·子 Agent 复用的组件 / 规则 / 机制 / CLI**，则**必出**一张「模块落地验收闭环卡」作为模块落地退出门禁——三段式（Xa 案例套件 → Xb 人在真实环境实跑回填 → Xc 回读出结论）、**非 S-item**、优先级 P0/P1、**依赖全部交付卡 DONE 后启动**；本轮**无此类可交付内容** → 升级 Owner 判定 **REOPEN M2**（范围太粗），**不静默跳过**。卡型字段标注 / 三段式各段职责 / 先例双锚见图纸 `07-M5 Roadmap 拆解.md` §3.1（本步只确立"必出 + 触发"，**不复制 schema**）。
4. **按优先级排序**：P0/P1/P2 分组形成总览表；卡 ID 按 `RM-YYYY-NNN` 约定全局递增（图纸 `07-M5` §8），已 CANCELLED 的 ID 不复用。
5. **核验依赖关系无环**：检查全部卡的 `dependencies` 字段构成有向无环图；存在环 → 回到步骤 1/2 调整拆分。
6. **写 `project/roadmap.md`**：含 frontmatter（version / updated / status / upstream_scope_version 对齐 M2 版本）+ 总览表 + 卡片详情。
7. **拆解失败的回退**：拆不出可独立交付的卡 → 升级 Owner 判定 REOPEN M2（范围太粗）或 REOPEN M3（架构耦合太强），不在本 Skill 内强行拆卡。

## 5. 产出物
- `proj-*/m5_roadmap/`（当次元流程实例的 M5 阶段落点；实例目录运行时才产生）；
- **实际落地件**：`project/roadmap.md`（总览 + 卡片详情 + 卡生命周期状态承载）。
- **验收闭环卡（若本轮含交付卡）**：作为模块落地退出门禁卡纳入 `roadmap.md`（卡型定义见图纸 `07-M5 Roadmap 拆解.md` §3.1）。

`roadmap.md` 完整结构（frontmatter / 总览表 / 卡 11 字段 / 状态机）的权威定义见图纸 `docs/stage-02-全生命周期拓展/02-体系设计/07-M5 Roadmap 拆解.md` §3–§4（本节不复制 schema，指针引用）。

## 6. 完成判据
- **每卡 T-shirt 估算 ≤ L**（XL 不得进入 Roadmap 卡，必须已拆分）；
- **依赖关系无环**（全部卡 `dependencies` 构成 DAG）；
- 每卡 11 字段齐备，`upstream_scope_version` 与 M2 scope.md 版本对齐；
- **Reviewer 评审通过**（`APPROVED`，或 `APPROVED_WITH_CONDITIONS` 经 Owner 核验条件闭合，见 `.harness/rules/开发流程规范.md` DF-002 注记）——评审执行以 `../expert-reviewer/SKILL.md`（现行版）为准，本判据不复制其内部机制；评审轮次 ≤3 轮；
- **HITL-M5 通过**。
- **roadmap 含模块落地验收闭环卡？**（断言式 · M5 Reviewer 评审本判据时逐项勾选）——本轮**含交付卡 → 必「是」**（roadmap 须含一张验收闭环卡）；本轮**无可交付内容 → 必已升级 REOPEN M2**（不得静默跳过）。此判据即"**reviewer 靠 §6 自动兜底**"的落点，避免 M5 漏列验收卡（先例：codegraph RM-2026-109 首入 / research-phase RM-2026-114 v2 REOPEN 补加）。

## 7. 引用
- **执行者**：strategist 子 Agent（`.claude/agents/strategist.md`，角色矩阵见 09 图纸 §2）。
- **上游图纸（产出物 schema 权威）**：`docs/stage-02-全生命周期拓展/02-体系设计/07-M5 Roadmap 拆解.md`（五要素 / roadmap.md 结构 / 卡状态机 / REOPEN 场景 / 卡 ID 约定）。
- **骨架来源**：`docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md` §3.8。
- **评审**：`../expert-reviewer/SKILL.md`（指针引用，现行版为准）。
- **下游消费方**：10 阶段启动机制（Q8.1，`docs/stage-02-全生命周期拓展/02-体系设计/11-元流程与 10 阶段对接规范（Q8 三子议题落地）.md` §2 消费 Roadmap 卡——卡的标题/描述/验收作为阶段 1 spec 草稿初值，阶段 1 执行见 `../request-analysis/SKILL.md`，仅指针引用，本卡不改其内容）；ad-hoc 回流（Q8.2，对接规范 §3）。
