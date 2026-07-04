---
name: engineering-baseline
description: 元流程 M4 工程基线落地。把 M3 决策物理化为可运行项目骨架与定制 Rules 覆盖。
trigger_phase: M4
trigger: M3.3 PASSED · 模式 E REOPEN M4
inputs: M3.1/3.2/3.3 全部产出、stage-01 `.harness/rules/` 模板
outputs: proj-*/m4_baseline/ + 实际落 .harness/rules/ + 业务代码根 + CI/CD
version: 1.0.0
updated: 2026-06-12
spec: docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md
---

# Skill · 工程基线落地（engineering-baseline）

## 1. 目的
把 M3 架构决策**物理化**为可运行项目骨架：将 M3.3 产出的定制 Rules 覆盖到 `.harness/rules/`、把 M3.1/M3.2 决策实例化为初始仓库结构 / CI/CD 骨架 / 可观测性骨架。M4 PASSED 意味着项目「骨架就绪、可以开始跑 10 阶段填业务」。

## 2. 触发条件
- **M3.3 PASSED**（定制 Rules 已定型）→ 进入 M4；
- **模式 E REOPEN M4**（如：跑 10 阶段时发现 CI 骨架缺项、定制 Rules 实战暴露过严等，典型场景见图纸 `06-M4 工程基线落地.md` §8）。

由编排中枢（Application Owner）在元流程 M4 阶段委派 strategist 子 Agent 加载执行。

## 3. 输入
- M3.1 / M3.2 / M3.3 全部产出（`proj-*/m3_architecture/` 三个子目录：C4 视图、接口契约/QAS/横切关注点/数据架构、ADR 集合 + 定制 Rules）；
- stage-01 `.harness/rules/` 模板（覆盖前的现行三件套）；
- 触发为模式 E REOPEN M4 时：`revise_reason` 与受影响产出清单。

## 4. 步骤（SOP）
1. **落技术选型最终清单**：基于 M3.2/M3.3 ADR 集合，产出 `project/tech-stack.md`。
2. **直接覆盖 `.harness/rules/` 为定制版**：将 M3.3 产出的定制 Rules（含 `API 设计规范.md`）落到 `.harness/rules/` 同名文件**直接覆盖**——**不**在 `.harness/rules/_template-backup/` 移动或保留模板副本（模板历史通过 git / stage-01 封板基线文档追溯）；如确需 snapshot 留底，存入当次实例 `proj-*/m4_baseline/template_snapshot/<原文件名>` 并标注「非规范来源 · 仅作本次落地参考」（覆盖机制详见 `docs/stage-02-全生命周期拓展/02-体系设计/10-定制 Rules 沉淀与覆盖机制.md`，本 SOP 不复制其细节）。
3. **落初始仓库结构**：按 M3.1 容器图 + M3.3 定制版工程结构.md，建立业务代码根（如 `src/` / `api/` / `domain/`）。
4. **落 CI/CD 骨架**：按 M3.2 QAS + stage-01 CI 三条件（`status==SUCCESS && total_tests>0 && passed==total`），落 `.github/workflows/` 或对应平台配置。
5. **落可观测性骨架**：按 M3.2 横切关注点⑥，落日志/指标/追踪的最小集成（仅「能运行」的骨架，不含业务埋点）。
6. **`_PROJ_TEMPLATE/` 校验与按需增补**：`.harness/changes/_PROJ_TEMPLATE/` 是**哈尼斯仓制品、初版由实施阶段预制**——M4 阶段仅对其做**校验 / 按项目定制需要增补**，不负责从零产出（图纸 `06-M4` §3.1 归属订正）。
7. **执行 M4 机械化自检**（见 §6 完成判据），任一项失败即 BLOCKED，回到 M4 自身修复（不回退到 M3）。**失败回退**：落地过程暴露架构级问题（非自检项失败，如接口不可实现/技术选型冲突）→ 升级 Owner，触发模式 E REOPEN M3 对应子阶段（图纸 `06-M4` §2 五要素表）。

> **归属订正（08 §6）**：目标项目 M4 **不产** SKILL.md 实例——9 个 `.harness/skills/<name>/SKILL.md` 是哈尼斯仓制品、由实施阶段据 08 骨架产出；M4 由本 Skill 产出的是**目标项目制品**（仓库结构 / CI / 定制 Rules 实例等）。本 SOP 任何步骤不得新建或修改 SKILL.md。

## 5. 产出物
- `proj-*/m4_baseline/`（当次元流程实例的 M4 阶段落点；实例目录运行时才产生）；
- **实际落地件**：`.harness/rules/`（定制版覆盖）+ 业务代码根（初始仓库结构）+ CI/CD 配置 + 可观测性骨架 + `project/tech-stack.md`。

五大产出物清单与各自落点/上游依据的权威定义见图纸 `docs/stage-02-全生命周期拓展/02-体系设计/06-M4 工程基线落地.md` §3（本节不复制 schema，指针引用）。

## 6. 完成判据
- **M4 §5 四项机械化自检全部通过**（任一失败即 BLOCKED）：
  1. 项目能 `pytest --collect-only` 不报错（或项目选定技术栈的等价收集检查）；
  2. `.harness/rules/` 下定制版三件套已就位（文件存在 + 头部 frontmatter 含本项目标识）；
  3. CI 配置语法合法（platform-specific lint，如 `actionlint`）；
  4. `project/` 顶层 M0–M4 产出文件齐备且各 frontmatter status==PASSED（**`project/roadmap.md` 不在 M4 自检范围**，归 M5 质量门禁）。
- 项目选定的类型/静态检查通过（如 Python 项目的 mypy / pyright）。
- **Reviewer 评审通过**（`APPROVED`，或 `APPROVED_WITH_CONDITIONS` 经 Owner 核验条件闭合，见 `.harness/rules/开发流程规范.md` DF-002 注记）——评审执行以 `../expert-reviewer/SKILL.md`（现行版）为准，本判据不复制其内部机制；评审轮次 ≤2 轮。
- **HITL-M4 通过**。

## 7. 引用
- **执行者**：strategist 子 Agent（`.claude/agents/strategist.md`，角色矩阵见 09 图纸 §2）。
- **上游图纸（产出物 schema 权威）**：`docs/stage-02-全生命周期拓展/02-体系设计/06-M4 工程基线落地.md`（五要素 / 五大产出物 / 自检 / REOPEN 场景）；`docs/stage-02-全生命周期拓展/02-体系设计/10-定制 Rules 沉淀与覆盖机制.md`（Rules 覆盖机制详化）。
- **骨架来源**：`docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md` §3.7。
- **评审**：`../expert-reviewer/SKILL.md`（指针引用，现行版为准）。
- **下游消费方**：M5（`../roadmap-planning/SKILL.md` 消费 `tech-stack.md`）；10 阶段全流程（全部 M4 产出是每张卡的运行环境——其中阶段 3 `../coding-skill/SKILL.md` 消费定制版 `.harness/rules/`，仅指针引用，本卡不改其内容）。
