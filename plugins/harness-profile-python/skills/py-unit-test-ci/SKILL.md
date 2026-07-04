---
name: py-unit-test-ci
description: Python 栈 CI 接线操作 how——pip install 依赖装配 + pytest -q（testCommand 实做）+ parse_pytest_summary.sh 接线（outputParser 实做）+ 三条件门禁采集 + 回退路由 Python 信号；判定式引用恒等不改本质（OQ-2/OQ-4）。
trigger_phase: 8
trigger: 阶段8 CI 验证（Python 栈 · 与核心 unit-test-ci 配合，承载 pip/pytest/parse_pytest_summary.sh 接线 how）
inputs: 已推送 Python 代码、阶段5/6 单测产出、绑定声明 python-binding.md、parse_pytest_summary.sh
outputs: ci_result/ci_result.md
version: 1.0.0
updated: 2026-06-28
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: python
---

# Skill · Python CI 验证接线（py-unit-test-ci）

> **栈特定层 · Python CI how**。本 skill 承载 RM-127 从核心 `unit-test-ci` 去串掉的 **`pip install` + `pytest -q` + `parse_pytest_summary.sh` 接线** SOP；与栈无关骨架 `plugins/harness-core/skills/unit-test-ci/` **配合**（骨架管「三条件门禁判定 + 采集填表 + 回退路由」的栈无关流程，本 skill 管「Python 栈下命令/解析器怎么接」）。
> **判定式恒等不改本质（OQ-4 · C-3）**：三条件门禁 `status==SUCCESS && total>0 && passed==total`（= GateContract `exit==0 && total>0 && passed==total`）**引用 api-design §1.2 / API-BL-2 · 不重定义**；本 profile 只换 `testCommand`/`outputParser`，判定本体跨 profile 恒等（AR-LY-3）。

## 1. 目的

在代码推送后执行 Python 测试验证，以**可程序化判定**的三条件门禁填写 `ci_result.md`，避免「状态 SUCCESS 但用例数为 0」假绿。命令/解析实值由绑定声明 `python-binding.md`（`testCommand()` / `outputParser()`）给出。

## 2. 触发条件

进入 **阶段8**（阶段7 推送成功）且 `stack` 为 Python 时，与核心 `plugins/harness-core/skills/unit-test-ci/` 一并由编排中枢加载。

## 3. 输入

- 本次变更的 git 提交 / 分支；阶段5/6 单测报告与用例清单；
- 绑定声明 `../../profile/python-binding.md`（`testCommand()` = `pytest -q` / `outputParser()` 引用 `parse_pytest_summary.sh`）；
- 输出解析器 `.harness/scripts/parse_pytest_summary.sh`（不重写不搬移）；
- 业务子项目路径（A 轮默认 `harnessdemo/price-service/`，实值见 `HARNESS_CONFIG.yaml` `compare_path_a`；以 spec / Owner 指定为准）。

## 4. 步骤（SOP）

1. **依赖装配 + 执行测试**（`testCommand()` Python 实做）：在目标业务子项目目录下——
   - `python -m pip install -r requirements.txt`（或 `pip install -e .` · 依赖装配）；
   - `pytest -q 2>&1 | tee /tmp/pytest_out.txt`（`testCommand()` 等价测试命令 = `pytest -q`）。

   > 测试路径以 spec / Owner 指定为准；按变更影响面选测试路径（工具链改动须含对应工具测试目录）；**禁止未执行测试即填 SUCCESS**。

2. **outputParser 接线 + 采集指标**（`outputParser()` Python 实做 · 引用绑定声明 §3 维度适配）：把 stdout 喂入解析器——
   - `.harness/scripts/parse_pytest_summary.sh /tmp/pytest_out.txt` → 输出 `status=` / `total_tests=` / `passed=`；
   - 维度适配（绑定声明 `python-binding.md` §3）：`total_tests↔total`、`passed↔passed`、`status` 为 decision 非权威布尔投影；**判定决定权在数值 `passed==total`**。

   | `ci_result.md` 字段 | 取值说明 |
   |---|---|
   | `status` | 解析器输出（退出码 0 且 `failed==0 && total>0` → `SUCCESS`，否则 `FAILURE`） |
   | `total_tests` | 解析器 `total_tests`（= `passed+failed+skipped`）；**解析失败显式 FAILURE 且置 0，不静默置 0 当成功**（API-BL-3） |
   | `passed` | 解析器 `passed`；须 `passed == total_tests` 且 `total_tests > 0` |

3. 按模板填三条件表与结论（见 `plugins/harness-core/_template/_TEMPLATE/ci_result/ci_result.md`）。

4. **不通过时回退**（对接 `plugins/harness-core/rules/开发流程规范.md §2.1` · Python 信号）：
   - `total_tests == 0` → 阶段5（单测编写）；
   - 语法/导入错误、`pytest` 收集失败、`pip install` 失败 → 阶段3（编码实现）。

## 5. 产出物

- `../../changes/<变更目录>/ci_result/ci_result.md`（含真数 · 阶段8 全量复跑取绝对数，禁伪造计数）。

## 6. 完成判据（必须全真，禁止只看 status）

- `status == SUCCESS`；
- `total_tests > 0`；
- `passed == total_tests`；
- 三者同时满足方视为门禁通过（= GateContract `exit==0 && total>0 && passed==total` 恒等）；`ci_result.md` 已落盘。

## 7. 引用

- 栈无关骨架（不复制 · 指回）：`plugins/harness-core/skills/unit-test-ci/`（三条件门禁判定 + 采集 + 回退路由）。
- 绑定声明：`../../profile/python-binding.md`（`testCommand()` / `outputParser()` / GateContract 引用恒等 + §3 维度适配）。
- 输出解析器：`.harness/scripts/parse_pytest_summary.sh`（引用对象 · 不重写不搬移）。
- 模板：`plugins/harness-core/_template/_TEMPLATE/ci_result/ci_result.md`；门禁：`plugins/harness-core/rules/开发流程规范.md`（DF-002 / DF-009）。
