---
name: py-unit-test-write
description: Python 栈单测编写操作 how——pytest + FastAPI TestClient + conftest 夹具模式、改动驱动测试、真实并发用例 Python 写法、测试根 tests/（PY-4）；引用 §3 PY-4 与绑定声明不复制（OQ-2）。
trigger_phase: 5
trigger: 阶段5 单元测试编写（Python 栈 · 与核心 unit-test-write 配合，承载 pytest/TestClient/conftest how）
inputs: 阶段4 通过的 Python 代码与改动接口清单、绑定声明 python-binding.md、项目编码规范.md §3 PY-4
outputs: pytest 测试模块、单测报告
version: 1.0.0
updated: 2026-06-28
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: python
---

# Skill · Python 单元测试编写（py-unit-test-write）

> **栈特定层 · Python 测试 how**。本 skill 承载 RM-127 从核心 `unit-test-write` 去串掉的 **pytest + FastAPI `TestClient` + `conftest` 夹具**编写 SOP；与栈无关骨架 `plugins/harness-core/skills/unit-test-write/` **配合**（骨架管「改动驱动 / 覆盖映射 / 真实并发纪律」的栈无关原则，本 skill 管「Python 栈下怎么写」）。
> **引用不复制（OQ-2 · C-3 单源）**：测试根/命名约定权威在 `项目编码规范.md §3 PY-4`，测试命令实值在绑定声明 `python-binding.md` `testCommand()`；本 skill 不重定义 PY-4 约束。

## 1. 目的

为本次 Python 改动编写**有业务价值**的 pytest 用例，保障阶段8 门禁 `total_tests > 0 && passed == total` 且可回归。

## 2. 触发条件

进入 **阶段5**（阶段4 编码评审通过且 HITL-3 通过 · 可与阶段4 并行）且 `stack` 为 Python 时，与核心 `plugins/harness-core/skills/unit-test-write/` 一并加载。

## 3. 输入

- 阶段4 通过的 Python 代码与改动接口/API 清单；
- 绑定声明 `../../profile/python-binding.md`（`testCommand()` = `pytest -q`）；
- 测试根/命名约定：`plugins/harness-core/rules/项目编码规范.md §3 PY-4`（测试放 `tests/`，用例 `test_*.py`）；
- 可用时通过 MCP 查询被改动接口的线上真实出入参构造数据。

## 4. 步骤（SOP）

1. **改动驱动**：改了哪个表现/业务/数据层方法就测哪个，而非只测无关模块（覆盖映射：接口 → 测试文件/用例名）。

2. **测试夹具 `conftest.py`**（PY-4 测试根 `tests/`）：在 `tests/conftest.py` 定义 pytest fixture——
   - FastAPI app 实例（经被测 `create_app()` app 工厂构造）；
   - `fastapi.testclient.TestClient(app)` 作 HTTP 测试客户端 fixture；
   - 必要的 DB/外部依赖夹具（贴近线上默认配置，见第 5 步）。

3. **用例组织**：测试模块落 `tests/test_*.py`（PY-4 命名）；用 `TestClient` 对 router 发请求断言状态码 + 响应体；service/repository 层可直接单元调用断言。覆盖**正常路径 + 关键边界/异常路径**（含业务 `error.code` 经 HTTP 端到端可达）。
   - 如本卡涉及 API · 含契约测试用例（契测模板见 `.harness/templates/contract-testing/`）。

4. **迭代范围**：迭代期（写→跑→改循环）只跑**改动相关子集**——`pytest -q tests/test_<改动模块>.py`（`testCommand()` 限定到改动相关测试模块）；全量套件留**阶段8 门禁**（`py-unit-test-ci` / `unit-test-ci`）一次执行。

5. **测试配置贴近线上默认**：夹具默认配置贴近线上默认（尤其持久化/并发开关，如 SQLite WAL）；确有必要偏离须在夹具处**显式加注理由**并纳入阶段4 评审。

6. **并发正确性须真实并发用例**：凡声称强一致/计数正确性（如「M 次请求 == count M」），须用 **`threading`/`concurrent.futures` 多线程**或**真实 HTTP 客户端**（`httpx` 并发）发起真实并发，断言成功数 == count 且**无 5xx**；**不得**仅以进程内单连接 `TestClient` 顺序调用充当并发证据。

7. 产出 `unit_test/` 下报告，列出覆盖映射（接口 → 测试文件/用例名）。

## 5. 产出物

- pytest 测试模块（落 `tests/`，命名 `test_*.py` · PY-4，或 spec 约定路径）；
- `../../changes/<变更目录>/unit_test/unit_test_report_vN.md`。

> 报告精简：本 SKILL 产出的报告类产物须满足 `plugins/harness-core/rules/开发流程规范.md` **DF-012**（内容硬约束 + 100 行软自检线 + 证据优先 + 不硬截断）。

## 6. 完成判据

- 被改动接口均有对应 pytest 用例（覆盖映射成立）；
- 本地确认 = 改动相关子集测试**全绿**（`pytest -q` 限定到改动相关模块；实值见绑定声明 `testCommand()` / `HARNESS_CONFIG.yaml`）；全量套件验证归**阶段8 门禁**；
- 为阶段8 提供可执行用例（`total_tests > 0 && passed == total`）；
- 若声称并发/强一致：有真实并发用例（非进程内单连接）且断言无 5xx；夹具默认配置贴近线上默认或对偏离显式加注。

## 7. 引用

- 栈无关骨架（不复制 · 指回）：`plugins/harness-core/skills/unit-test-write/`（改动驱动 / 覆盖映射 / 真实并发纪律）。
- 绑定声明：`../../profile/python-binding.md`（`testCommand()` = `pytest -q`）。
- 测试根/命名约定：`plugins/harness-core/rules/项目编码规范.md §3 PY-4`。
- 下游：`../py-unit-test-ci/`、`plugins/harness-core/skills/unit-test-ci/`（阶段8）、`plugins/harness-core/skills/expert-reviewer/`（阶段6）。
