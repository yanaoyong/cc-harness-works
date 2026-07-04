---
name: py-coding-skill
description: Python 栈（FastAPI/pytest/ruff）编码实现操作 how——承载 RM-127 从核心 coding-skill 去串掉的 Python 编码步骤序列；引用 §3 PY 约束与 8 份分层 spec 不复制（OQ-2）。
trigger_phase: 3
trigger: 阶段3 编码实现（Python 栈 · 与核心 coding-skill 配合，承载 Python 操作 how）
inputs: 已 APPROVED 的 spec.md / tasks.md、绑定声明 python-binding.md、项目编码规范.md §3 PY、coding-skill/specs/ 8 份分层 Spec
outputs: Python 代码、coding_report_vN.md
version: 1.0.0
updated: 2026-06-28
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: python
---

# Skill · Python 编码实现（py-coding-skill）

> **栈特定层 · Python how**。本 skill 承载 RM-127 从核心 `coding-skill` 去串掉的 **Python 操作 SOP（步骤/命令序列）**；与栈无关骨架 `plugins/harness-core/skills/coding-skill/` **配合**（骨架管「按 `layeredSpecMapping()` 逐层 + 守 GEN 硬约束」的栈无关流程，本 skill 管「Python 栈下具体怎么做」）。
> **引用不复制（OQ-2 · C-3 单源）**：每处 how 旁注指向权威——约束（what）在 `项目编码规范.md §3 PY-x`、分层 spec 在 `coding-skill/specs/NN-*.md`、命令实值在绑定声明 `python-binding.md`；本 skill **不重定义** PY-* 约束语义。

## 1. 目的

在 Python（FastAPI / pytest / ruff）栈下，按 `layeredSpecMapping()` 返回的 8 份后端分层 Spec 逐层落地代码，产出符合 `项目编码规范.md §3 PY` 与 `工程结构.md ES` 的实现 + `coding_report_vN.md`。

## 2. 触发条件

进入 **阶段3**（阶段2 APPROVED 且 HITL-2 通过）且 `HARNESS_CONFIG.yaml` `stack` 解析为 Python 时，与核心 `coding-skill` 一并加载；**按当前所处层加载对应分层 Spec**（见 `plugins/harness-core/skills/coding-skill/specs/README.md`），不全量加载。

## 3. 输入

- 已 APPROVED 的 `spec.md` / `tasks.md`；
- 绑定声明 `../../profile/python-binding.md`（testCommand / outputParser / layeredSpecMapping / RequiredCommandRef 实值）；
- 约束（what）：`plugins/harness-core/rules/项目编码规范.md §3 PY-1~5`；分层（structure）：`plugins/harness-core/rules/工程结构.md §2.1 ES`；
- 8 份分层 Spec：`plugins/harness-core/skills/coding-skill/specs/01-api-router.md` ~ `08-openapi.md`；
- 既有 Python 代码（变更前先读懂，避免模仿错误 Pattern，如浮点存金额 / httpx 无超时降级）。

## 4. 步骤（SOP）

1. **范围与分层归属**：读 spec/tasks，按 `工程结构.md §2.1` 确认改动落在 `api/` → `service/` → `repository/` → `adapter/` → `model/` 哪一层；依赖**单向向下**（ES-001/002）。

2. **逐层实现**（对接 8 份分层 Spec · `layeredSpecMapping()` 在原地引用）：
   - **表现层 `api/*_router.py`**（→ `specs/01-api-router.md` · PY-1）：FastAPI `APIRouter` 路由；入参/出参用 Pydantic 模型校验；router **只做校验 + 编排 + 委托 service，不写大段业务逻辑**（GEN-4 / PY-1 载体）。HTTP 异常用 `HTTPException` / 异常处理器映射，确保业务 `error.code` 端到端可达、未被框架校验器抢先改写状态码。
   - **应用/模型层 `model/`（Pydantic schemas）**（→ `specs/02-schemas.md` · PY-5）：请求/响应 DTO 用 `pydantic.BaseModel` + `Field(...)` 约束；金额字段 `int`（分），见第 3 步。
   - **业务层 `service/`**（→ `specs/03-service-contracts.md` / `04-domain-logic.md`）：业务封装与编排；FastAPI app 经 `main.py` app 工厂（`def create_app() -> FastAPI:`）装配 router/依赖。
   - **数据层 `repository/`**（→ `specs/05-schema-migration.md` / `06-repository.md` · ES-002）：仓储模式；**禁止 import api**（逆向依赖违 ES-002）。
   - **适配层 `adapter/`**（→ `specs/07-adapter.md` · PY-3）：外部 HTTP 调用见第 4 步。
   - **文档层**（→ `specs/08-openapi.md`）：FastAPI 自动 OpenAPI / 文档约定。

3. **金额 int（分）整数运算**（GEN-1 / PY-2 · 权威 `项目编码规范.md §3 PY-2`）：金额/价格字段用 `price_cents: int`（最小单位分），**禁 `float`/`double` 存金额**；折扣等用整数运算（如 `price_cents * pct // 100`），无 `float` 中间量。

4. **httpx 超时 + 降级**（GEN-2 / PY-3 · 权威 `项目编码规范.md §3 PY-3` · `specs/07-adapter.md`）：所有外部 HTTP/RPC 用 `httpx` 调用须显式设 `timeout=`（如 `httpx.Client(timeout=...)` 或 `httpx.get(url, timeout=...)`）+ 失败降级路径（超时/连接错误时返回降级值或显式错误，不裸抛吞）。**此项违规 = 评审默认 MUST FIX**（R-002 强绑定）。

5. **不过度重构 + 复用**（GEN-7）：不做超出需求范围的重构；优先复用项目内已有包（防熵增）。

6. **lint 静态检查**：以 **`ruff`** 对改动文件做静态检查（`ruff check <改动路径>`），消除 lint 告警；命名 `snake_case`、Pydantic 模型归 `model`/`schemas`（PY-5 / ES-004）。`ruff` 为本 profile RequiredCommandRef 声明命令（见 `python-binding.md` §1）。

7. **构建/收集校验**（绑定层"依赖装配 + 构建/收集校验"的 Python 实做）：在业务子项目根（`HARNESS_CONFIG.yaml` `compare_path_a` 等）执行——
   - `python -m compileall src/`（语法/导入装配校验）；
   - `python -m pytest --collect-only -q`（用例收集校验，确认无收集错误）。
   收集/编译失败 → 回退阶段3 修复（对接 `开发流程规范.md §2.1`）。

8. **产出 `coding_report_vN.md`**：改动点 + 分层对照 + 硬约束自检（金额 int / httpx 超时降级 / router 瘦身 / import 方向）+ 风险。

## 5. 产出物

- Python 代码变更（A 轮在 `HARNESS_CONFIG.yaml` `compare_path_a` 指向的业务子项目；其他以 spec 为准）；
- `../../changes/<变更目录>/coding/coding_report_vN.md`（版本递增）。

> 报告精简：本 SKILL 产出的报告类产物须满足 `plugins/harness-core/rules/开发流程规范.md` **DF-012**（内容硬约束 + 100 行软自检线 + 证据优先 + 不硬截断；`spec.md`/`tasks.md` 豁免）。

## 6. 完成判据

- `python -m compileall` + `pytest --collect-only` 无错（构建/收集通过 · 第 7 步）；
- `ruff check` 改动文件无遗留告警（第 6 步）；
- 对照 8 份分层 Spec / `项目编码规范.md §3 PY` 无 MUST 违反（金额 int / httpx 超时降级 / router 瘦身 / import 单向）；
- `coding_report_vN.md` 齐全，交付阶段4 评审。

## 7. 引用

- 栈无关骨架：`plugins/harness-core/skills/coding-skill/`（逐层 + GEN 硬约束栈无关流程）；分层 Spec 索引：`plugins/harness-core/skills/coding-skill/specs/README.md`。
- 绑定声明：`../../profile/python-binding.md`（testCommand / layeredSpecMapping / RequiredCommandRef 实值）。
- 约束（what）：`plugins/harness-core/rules/项目编码规范.md §3 PY-1~5`；分层：`plugins/harness-core/rules/工程结构.md §2.1 ES`。
- 下游：`../py-code-review/`、`plugins/harness-core/skills/code-review/`、`plugins/harness-core/skills/expert-reviewer/`（阶段4）。
