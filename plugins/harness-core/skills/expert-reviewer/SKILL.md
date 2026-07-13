---
name: expert-reviewer
trigger: 阶段2 计划评审 / 阶段4 执行评审 / 阶段6 单测评审
inputs: 待评审产出物（spec/tasks 或 代码/报告 或 测试）
outputs: 评审报告 *_review_vN.md
version: 1.1.0
updated: 2026-06-11
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
---

# Skill · 专家评审（expert-reviewer）

> 铁律：评审角色与执行角色**必须分离**。本 Skill 由 Reviewer 角色加载，仅评审、不改代码。

## 1. 目的
以独立视角审视产出物，前移质量发现，拦截需求/编码/测试中的缺陷。

## 2. 触发条件
- 阶段2：计划评审（spec.md + tasks.md）；
- 阶段4：执行评审（编码实现是否满足计划与需求）；
- 阶段6：单测评审。

## 3. 输入
- 对应阶段的产出物；
- 相关 Rules（作为评审依据）。

## 4. 步骤（SOP）

> **起手批量并发首读（proposal-012 §3② · 一条消息并发 · 按评审类型枚举）**：确定类型后，把该阶段独立首读项在**一条消息内并发**读取——**阶段2 计划评审** = `spec.md` + `tasks.md`；**阶段4 执行评审** = `spec.md` + `coding/coding_report_vN.md` + `git diff --stat`；**阶段6 单测评审** = 两份报告并发（`unit_test/unit_test_report_vN.md` + `coding/coding_report_vN.md`）+ `git diff --stat`。

1. 确定评审类型（计划 / 执行 / 单测）。
2. 对照 Rules 与需求逐项检查（分层依赖、硬约束、覆盖面等）。
3. 形成意见，**每条意见格式 = 问题描述 + 修改建议 + 优先级（MUST FIX / LOW / INFO）**。
4. 给出结论（三态枚举）：`APPROVED` / `APPROVED_WITH_CONDITIONS` / `REVISION REQUIRED`（第三态适用条件与闭合方式见 §4.2）。
5. 落盘评审报告（含必填章节）；超过循环上限则升级人工。

> **行为遵行维度 · 受益场景留痕缺失记 LOW（守 ADR-005 旁路不阻断）**：受益场景（CG-Q / WK-Q 命中）下产物若无 cg / wiki 工具调用证据，记 **LOW（非 MUST FIX）**——cg / wiki 是旁路工具，留痕缺失只提示不阻断交付，**不进 pass/fail 门禁**（与 `code-review/SKILL.md` §4 第 10 条同口径；判据 + 痕迹形态见 `.harness/acceptance/_behavioral-dimension/`，仅「受益场景下」无证据才记 LOW · 防假违规）。

> **验收闭环卡 Xa 套件 · §6 回填模板三节结构核对（评审验收闭环卡时 · 阶段2/4）**：被评审对象是验收闭环卡的 Xa 案例套件时，逐 case 核对其 §6 回填模板是否含【运行前 · 前置验证 / 造条件】【运行中需要进行的操作】【运行后 · 恢复 / 清理】三节（叠加在 实际输出 + 偏差 之上）；缺任一节 = **MUST FIX**。三节定义与可复制骨架见 `docs/stage-02-全生命周期拓展/02-体系设计/07-M5 Roadmap 拆解.md` §3.1「Xa 回填模板结构契约」——**指针引用、不复制定义**（守单源 · 防双源漂移）。

> **验收闭环卡 Xa 套件 · result stub 存在性核对（评审验收闭环卡时 · 阶段2/4）**：被评审对象是验收闭环卡的 Xa 案例套件时，还须逐 case 核对 `../results/<CASE-ID>-result.md` 是否已预建；缺 stub = **MUST FIX**。命名规则与预建契约见 `docs/stage-02-全生命周期拓展/02-体系设计/07-M5 Roadmap 拆解.md` §3.1「Xa result stub 预建契约」——**指针引用、不复制定义**（守单源 · §3.1 为 SSOT · 防双源漂移）。

### 4.1 验证档位（阶段4/6 复验分档）

档位选择**必须在评审报告头部声明**（字段：**验证档位 + 选档理由**）；无声明视为报告不合格。

- **抽查档（默认）**：当 generator 已留档机械证据——**diff 基线、全绿测试日志、退出码记录**——时采用；reviewer 独立复验 **2–3 个采样点**，不重建全量对抗验证。
- **全量档（升级）**：满足任一条件即升级：
  1. 证据缺失或不完整；
  2. 涉及高风险点（**冻结契约、安全、不可逆操作**）；
  3. 抽查发现任一采样点不符。

### 4.2 条件式通过（APPROVED_WITH_CONDITIONS）

- **适用条件（全部满足才可用）**：所有 MUST FIX 均为**文档级一两句话修订**，不触及代码/脚本/hook/测试；报告须列出**条件清单**（逐条 = 文件 + 修订点 + 验收口径）。
- **闭合方式**：Owner 核验条件清单逐条落实后，该评审即视为 `APPROVED`，在 `summary.md` 记录核验结论，**免起 v2 评审**；该核验**不计入 DF-005 评审轮次**（U4 决议：Owner 核验非 reviewer 调用，轮次上限仍只约束 REVISION→v2 循环）。
- **强制 v2**：任何**代码级 MUST FIX** 仍强制 `REVISION REQUIRED` + Owner 新调用 v2，不得套用条件式通过。
- **与 reviewer.md「ONE pass」兼容性**：条件式通过的闭合者是 **Owner（核验文档修订）而非 reviewer**——不产生第二次 reviewer 调用，也不要求 reviewer 自启 v2 或假设上游已修，与 `.claude/agents/reviewer.md`"严格约束（不可越权）"（单次产出 / 不假设上游已修 / 不跑 v2/v3）兼容，§6.1 默认行为不变；`myCLAUDE.md`"reviewer 委派契约"节仅为指向 reviewer.md 的指针、无结论枚举措辞，无需同步。

## 5. 产出物
- 计划评审：`../../changes/<变更目录>/request_analysis/review/spec_review_vN.md`、`tasks_review_vN.md`
- 执行评审：`../../changes/<变更目录>/coding/review/code_review_vN.md`
- 单测评审：`../../changes/<变更目录>/unit_test/review/*_vN.md`
（版本递增、旧版永不删）

> 报告精简：本 SKILL 产出的报告类产物须满足 `../../rules/开发流程规范.md` **DF-012**（报告预算：内容硬约束 + 100 行软自检线 + 证据优先 + 不硬截断；`spec.md`/`tasks.md` 豁免）。

## 6. 完成判据
- 评审报告存在且含必填章节（问题列表 + 结论）；
- 结论为 `APPROVED` 时 MUST FIX 数为 0；
- 结论为 `APPROVED_WITH_CONDITIONS` 时，MUST FIX 全部为文档级条件项且条件清单（文件 + 修订点 + 验收口径）存在（见 §4.2）；
- 循环轮次未超上限（需求 ≤3 / 编码/单测 ≤2；条件式通过的 Owner 核验不计入轮次）。

### 6.1 默认行为（来自 `failure-record-003` §4.5.3 · A+B B 层）

适用于所有 reviewer 调用，除非 Owner 显式覆盖：

- **默认行为**：每次调用默认只产出 v1；不主动迭代到 v2/v3。
- **循环上限语义**：评审循环 ≤3 轮是**上限**——指 Owner 可以最多发起 3 次调用，**不是**"每次调用应该跑到 3 轮"。
- **v2/v3 触发条件**：仅当 Owner 在新调用中显式说"基于已落地的 v1.x 修订做 v2"时才启动（v1.x 覆盖 v1.1/v1.2/v1.3 多轮修订；防幻觉的关键词是"已落地"——不是版本号细粒度）。
- **不假设上游已修**：评审基于**调用时刻**变更目录的真实文件状态；任何"假设已修"的推理是越权。

## 7. 引用
- 规则：`../../rules/`（全部，作为评审依据）
- 意见格式与门禁：`docs/stage-01-Harness体系建设/03-质量与改进/08-质量门禁与反馈回路规范.md §5`
- 报告模板：`docs/stage-01-Harness体系建设/03-质量与改进/09-变更管理与持久化记忆规范.md` / `../../_template/_TEMPLATE/`
