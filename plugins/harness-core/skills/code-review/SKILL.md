---
name: code-review
trigger: 阶段4 编码评审（与 expert-reviewer 配合）
inputs: 阶段3 代码与 coding_report_vN.md
outputs: 辅助检查项（并入 code_review 报告或 checklist 附页）
version: 1.2.0
updated: 2026-06-16
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: vendor-neutral（具体栈见 HARNESS_CONFIG.yaml · 栈特定载体见 ../../rules/项目编码规范.md §3 PY / §4 FE）
---

# Skill · 代码检查（code-review）

> 与 `expert-reviewer` 执行评审配合；**不替代** reviewer 的评判与结论。

## 1. 目的

对编码产出做结构化检查（分层、硬约束、对比测试陷阱 T1～T5），为 `expert-reviewer` 提供输入。栈无关语义见 `../../rules/项目编码规范.md §2 通用层 GEN`，栈特定载体见同文件 §3/§4 栈特定层。

## 2. 触发条件

进入 **阶段4** 时与 `expert-reviewer` **一并加载**；由 **Reviewer** 执行，Generator 不参与。

## 3. 输入

- `coding/coding_report_vN.md` 与代码 diff；
- `../../rules/工程结构.md`、`../../rules/项目编码规范.md`。

## 4. 步骤（SOP）

1. 对照检查清单逐项勾选（见下表）。
2. 发现问题写入评审意见（问题 + 建议 + 优先级 MUST FIX/LOW/INFO），汇总进 `code_review_vN.md`。
3. 不单独宣布 APPROVED；**以 expert-reviewer 结论为准**。

### 检查清单（栈中立 · 通用语义检查项 · 栈特定载体指向 `../../rules/项目编码规范.md §3/§4`）

| # | 检查项 | 依据 |
|---|---|---|
| 1 | import 分层无逆向（repository 不 import api） | ES-001/002 |
| 2 | 新增金额字段为 **`int`（分）**，无 `float` 存金额 | R-001 / CODE-001 |
| 3 | 外部 HTTP/RPC 客户端调用有 **timeout（超时）** 与失败降级（栈特定 HTTP 客户端载体见 `项目编码规范.md §3 PY-3 / §4 FE-3`） | GEN-2 / R-002 |
| 4 | 无密钥入库迹象 | R-005 |
| 5 | 改动范围未超出 spec/tasks | 需求边界 |
| 6 | **api/router** 无大段业务逻辑，已委托 **service** | CODE-003 |
| 7 | 折扣等金额运算使用 **整数运算**，无 `float` 中间量 | R-001（T5） |
| 8 | 逐错误码核验：业务 `error.code` 经 HTTP **端到端可达**，框架层校验器（数据模型字段约束 / 路由路径 `pattern` 校验 / 中间件——栈特定载体见 `项目编码规范.md §3 PY`）未抢先拦截改写状态码 | D-003（stage2-001）|
| 9 | 测试环境配置**代表线上默认**（持久化/并发开关等）；并发正确性声称（强一致/计数）有**真实并发用例**支撑（多线程/真实 HTTP 客户端并发），非进程内单连接 | stage2-002 |
| 10 | **受益场景（CG-Q / WK-Q 命中）下产物有无工具（cg / wiki）调用证据？无 → 记 LOW（非 MUST FIX）** | 本卡行为遵行维度 · `.harness/acceptance/_behavioral-dimension/` |

> **检查清单第 3 条 · 强绑定**：本检查项命中 → 评审报告必须标 MUST FIX。对应规则 `项目编码规范.md` R-002 / CODE-002（违规默认 MUST FIX，豁免须经 HITL-3）。评审 Agent 不得自由心证下调到 INFO / LOW。

> **检查清单第 10 条 · 显著标 LOW（与第 3 条相反 · 守 ADR-005 旁路）**：本检查项命中（受益场景下无工具调用证据）→ 评审报告记 **LOW（非 MUST FIX）**，**不阻断交付**。与第 3 条 R-002 强绑定 MUST FIX **性质相反**，**切勿误套强绑定**：cg / wiki 是旁路工具，留痕缺失只提示「请人去看是否真受益」，不进 pass/fail 门禁。受益场景判据 + 痕迹形态见 `.harness/acceptance/_behavioral-dimension/benefit-scenarios.md`（R1）；**仅「受益场景下」无证据才记 LOW**（不满足受益场景 = 无痕迹不算违规，防假违规 · R1 §3）。

> **检查清单第 8/9 条 · 说明**：来源失败记录 `failure-record-stage2-001 §D-003`（错误码 HTTP 可达性 · 复现 3 次）与 `failure-record-stage2-002`（测试配置偏离线上 + 契约层缺真实并发覆盖 · 封板后实测）。两项均为静态评审固有盲区——纯读 service 逻辑判「符合」不足，须显式推演 API 边界拦截顺序、核对测试是否在代表性配置/真实并发下运行。

> **violations.log 起点处理**：每次评审 Skill 启动时，先读取 `.harness/improvement/static-scan-violations.log`，**按本变更目录 scope 过滤**（grep 当前变更目录所影响的文件路径前缀），过滤后集合视为本变更新增的违规集合。
>
> **BLOCKED 触发**：若过滤后集合非空 → 评审报告**必须**标 `BLOCKED`（在 `APPROVED` / `REVISION_REQUIRED` 二档之外的第三档，evidence 类专用）。BLOCKED 状态下游门禁视为未通过。
>
> **HITL-3 豁免出口**：Owner 在评审报告"豁免与例外"区块手写 `[HITL-3 豁免 · YYYY-MM-DD · <理由>]` 即视为通过；豁免后评审报告头部状态改为 `APPROVED (HITL-3 EXEMPTED)`，下游门禁视为通过。Agent **不可**代填豁免声明。

## 5. 产出物

- 检查项结果并入 `../../changes/<变更目录>/coding/review/code_review_vN.md`。

## 6. 完成判据

- 清单已覆盖且关键项无未记录的 MUST FIX；
- `code_review_vN.md` 已落盘且 expert-reviewer 结论为 APPROVED（MUST FIX 数 == 0）。

## 7. 引用

- 主评审：`../expert-reviewer/`
- 模板：`../../_template/_TEMPLATE/coding/review/code_review_v1.md`
- 规则：`../../rules/`
- 对比测试陷阱：`test/00-方案与决策/01-对比测试设计方案.md` §二（T1～T5）
