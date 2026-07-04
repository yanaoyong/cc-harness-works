---
name: py-code-review
description: Python 栈代码评审清单的栈特定载体——只补 httpx 超时/降级、Pydantic Field、import 分层方向、router 瘦身、金额 int 等 Python 框架载体检查点；栈无关语义项指回核心 code-review 不复制（OQ-2）。
trigger_phase: 4
trigger: 阶段4 编码评审（Python 栈 · 与核心 code-review + expert-reviewer 配合，补 Python 框架载体检查点）
inputs: 阶段3 Python 代码与 coding_report_vN.md、核心 code-review 检查清单、项目编码规范.md §3 PY
outputs: Python 框架载体检查项（并入 code_review_vN.md 或 checklist 附页）
version: 1.0.0
updated: 2026-06-28
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: python
---

# Skill · Python 代码评审载体（py-code-review）

> **栈特定层 · Python 评审载体**。本 skill **只补** Python 框架载体检查点；**栈无关语义检查项**（金额 int 语义 / 超时降级语义 / router 瘦身语义 / 密钥不入库 / 并发正确性 / 改动范围 / CG·WK 行为遵行等）**仍在核心 `plugins/harness-core/skills/code-review/` skill，不复制**（OQ-2 · C-3 单源）。与 `expert-reviewer` 执行评审配合，**不替代** reviewer 的评判与结论。
> **引用不复制**：每个检查项旁注权威——`项目编码规范.md §3 PY-x`（约束）/ `工程结构.md ES`（分层）；本 skill 不重定义 PY-* 约束语义。

## 1. 目的

在 Python（FastAPI / pytest / ruff）栈下，对编码产出补充**框架载体级**结构化检查，连同核心 `code-review` 栈中立清单一并为 `expert-reviewer` 提供输入。

## 2. 触发条件

进入 **阶段4** 时与核心 `plugins/harness-core/skills/code-review/` + `expert-reviewer` **一并加载**；由 **Reviewer** 执行，Generator 不参与。先跑核心 `code-review` 栈中立清单，再以本清单补 Python 载体。

## 3. 输入

- `coding/coding_report_vN.md` 与 Python 代码 diff；
- 核心栈中立检查清单：`plugins/harness-core/skills/code-review/SKILL.md`（金额/超时/router/密钥/并发等通用语义项）；
- 约束（what）：`plugins/harness-core/rules/项目编码规范.md §3 PY-1~5`；分层：`plugins/harness-core/rules/工程结构.md §2.1 ES`。

## 4. 步骤（SOP）

1. **先核栈中立项**：对照核心 `plugins/harness-core/skills/code-review/` 检查清单逐项勾选（通用语义项不在本 skill 重复）。
2. **再补 Python 框架载体检查点**（下表）；发现问题写入评审意见（问题 + 建议 + 优先级），汇总进 `code_review_vN.md`。
3. 不单独宣布 APPROVED；**以 expert-reviewer 结论为准**。

### Python 框架载体检查清单（栈特定 · 通用语义项见核心 code-review）

| # | Python 载体检查项 | 权威依据 |
|---|---|---|
| P1 | **httpx 超时/降级载体**：所有 `httpx` 外部调用显式 `timeout=`（`httpx.Client(timeout=...)` / `get(..., timeout=...)`）+ 失败降级路径在场（超时/连接错误不裸抛吞） | `项目编码规范.md §3 PY-3`（GEN-2 / R-002 载体 · `specs/07-adapter.md`） |
| P2 | **Pydantic 模型与 Field 约束**：请求/响应 DTO 为 `BaseModel`，字段约束用 `Field(...)`（如范围/正则）；金额字段类型为 `int`（分）非 `float` | `项目编码规范.md §3 PY-2 / PY-5`（GEN-1 载体 · `specs/02-schemas.md`） |
| P3 | **import 分层方向**：`repository/` 不 `import` `api/`；下层不 import 上层（单向向下） | `工程结构.md ES-001/002`（`specs/06-repository.md`） |
| P4 | **router 瘦身载体**：FastAPI 路由函数无大段业务/批量查库/折扣计算，已委托 `service/` | `项目编码规范.md §3 PY-1`（GEN-4 / CODE-003 载体 · `specs/01-api-router.md`） |
| P5 | **金额 int 整数运算载体**：折扣等金额运算为整数运算（如 `* pct // 100`），无 `float` 中间量 | `项目编码规范.md §3 PY-2`（GEN-1 / R-001 载体） |
| P6 | **错误码 HTTP 可达**：业务 `error.code` 经 `HTTPException`/异常处理器端到端可达，FastAPI 路径 `pattern` / Pydantic 校验器未抢先拦截改写状态码 | `code-review` 清单第 8 条（D-003）的 Python 载体推演 |
| P7 | **`ruff` 静态 lint**：以 `ruff check <改动路径>` 复核改动文件无遗留 lint 告警；命名 `snake_case`、Pydantic 模型归 `model`/`schemas`（PY-5） | `项目编码规范.md §3 PY-5`（`ruff` 为本 profile RequiredCommandRef 声明命令） |

> **P1 强绑定**：P1（httpx 超时/降级）命中 → 评审报告必须标 **MUST FIX**（R-002 / GEN-2 强绑定，与核心 `code-review` 第 3 条同档）；豁免须经 HITL-3 显式声明，评审 Agent 不得自由心证下调 LOW/INFO。
> **栈无关语义项不在本表**：密钥不入库、改动范围越界、CG·WK 行为遵行（受益场景无工具痕迹记 LOW）等仍在核心 `plugins/harness-core/skills/code-review/` 清单，本 skill 不复制、只指回。

## 5. 产出物

- Python 框架载体检查项结果并入 `../../changes/<变更目录>/coding/review/code_review_vN.md`（或其 checklist 附页）。

## 6. 完成判据

- Python 载体清单 P1~P7 已覆盖且关键项无未记录的 MUST FIX；
- 核心 `code-review` 栈中立清单已先行勾选；
- `code_review_vN.md` 已落盘且 `expert-reviewer` 结论为 APPROVED（MUST FIX 数 == 0）。

## 7. 引用

- 核心栈中立清单（不复制 · 指回）：`plugins/harness-core/skills/code-review/`；主评审：`plugins/harness-core/skills/expert-reviewer/`。
- 约束（what）：`plugins/harness-core/rules/项目编码规范.md §3 PY-1~5`；分层：`plugins/harness-core/rules/工程结构.md §2.1 ES`。
- 绑定声明：`../../profile/python-binding.md`（RequiredCommandRef `ruff`）。
- 模板：`plugins/harness-core/_template/_TEMPLATE/coding/review/code_review_v1.md`。
