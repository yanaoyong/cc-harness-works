---
name: fe-unit-test-ci
description: React+Vite 栈 CI 接线操作 how——npm/pnpm install 依赖装配 + vitest run（testCommand 实做）+ parse_vitest_summary.sh 接线（outputParser 实做）+ eval_gate_contract.sh 判定器 + 三条件门禁采集 + 回退路由 FE 信号；判定式引用恒等不改本质（C-5）。
trigger_phase: 8
trigger: 阶段8 CI 验证（React+Vite 栈 · 与核心 unit-test-ci 配合，承载 npm/vitest/parse_vitest_summary.sh 接线 how）
inputs: 已推送 FE 代码、阶段5/6 单测产出、绑定声明 react-vite-binding.md、parse_vitest_summary.sh、eval_gate_contract.sh
outputs: ci_result/ci_result.md
version: 1.0.0
updated: 2026-06-28
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: react-vite
---

# Skill · React+Vite CI 验证接线（fe-unit-test-ci）

> **栈特定层 · FE CI how**。本 skill 承载 RM-127 从核心 `unit-test-ci` 去串掉的 **`npm install` + `vitest run` + `parse_vitest_summary.sh` 接线** SOP；与栈无关骨架 `plugins/harness-core/skills/unit-test-ci/` **配合**（骨架管「三条件门禁判定 + 采集填表 + 回退路由」的栈无关流程，本 skill 管「React+Vite 栈下命令/解析器怎么接」）。
> **判定式恒等不改本质（C-5 · BL-INV-1）**：三条件门禁 `exit==0 && total>0 && passed==total`（= GateContract 冻结判定式）**引用 `eval_gate_contract.sh` 作权威单源 · 不重定义**；本 profile 只换 `testCommand`/`outputParser`（vitest 侧），判定本体跨 profile 恒等（RM-129 双向校验已证）。

## 1. 目的

在代码推送后执行 React+Vite 测试验证，以**可程序化判定**的三条件门禁填写 `ci_result.md`，避免「状态 SUCCESS 但用例数为 0」假绿。命令/解析实值由绑定声明 `react-vite-binding.md`（`testCommand()` / `outputParser()`）给出。

## 2. 触发条件

进入 **阶段8**（阶段7 推送成功）且 `stack` 为 React+Vite 时，与核心 `plugins/harness-core/skills/unit-test-ci/` 一并由编排中枢加载。

## 3. 输入

- 本次变更的 git 提交 / 分支；阶段5/6 单测报告与用例清单；
- 绑定声明 `react-vite-binding.md`（实体未迁入 plugin · 待补 · 受控前向引用，见 fe-coding-skill §3；`testCommand()` = `vitest run` / `outputParser()` 引用 `parse_vitest_summary.sh`）；
- 输出解析器 `.harness/scripts/parse_vitest_summary.sh`（RM-129 产物 · 不重写不搬移）；
- 判定器 `.harness/scripts/eval_gate_contract.sh`（RM-129 产物 · 冻结判定式权威单源）；
- FE 项目路径（实值见 `HARNESS_CONFIG.yaml` 或 spec / Owner 指定）。

## 4. 步骤（SOP）

1. **依赖装配 + 执行测试**（`testCommand()` React+Vite 实做）：在目标 FE 项目目录下——
   - `npm install`（或 `pnpm install` 按 `package.json` lock 文件 · 依赖装配）；
   - `vitest run 2>&1 | tee /tmp/vitest_out.txt`（`testCommand()` 等价测试命令 = `vitest run`）。

   > 测试路径以 spec / Owner 指定为准；按变更影响面选测试路径（工具链改动须含对应工具测试目录）；**禁止未执行测试即填 SUCCESS**。

2. **outputParser 接线 + 采集指标**（`outputParser()` React+Vite 实做 · 引用 RM-129 解析器）：把 stdout 喂入 vitest 解析器——
   - `.harness/scripts/parse_vitest_summary.sh /tmp/vitest_out.txt > /tmp/vitest_triple.env`（将三元组写入临时文件）；
   - 再喂入判定器：`.harness/scripts/eval_gate_contract.sh /tmp/vitest_triple.env` + exit code → 输出 `gate=PASS|FAIL`（权威门禁判定）。

   | `ci_result.md` 字段 | 取值说明 |
   |---|---|
   | `status` | 解析器输出（vitest exit 0 且解析成功 → `SUCCESS`，否则 `FAILURE`）；**权威判定以 `eval_gate_contract.sh` 为准**（§6） |
   | `total_tests` | 解析器 `total_tests`（= `passed+failed`）；**解析失败显式 FAILURE 且置 0，不静默置 0 当成功**（API-BL-3） |
   | `passed` | 解析器 `passed`；须 `passed == total_tests` 且 `total_tests > 0` |

3. 按模板填三条件表与结论（见 `plugins/harness-core/_template/_TEMPLATE/ci_result/ci_result.md`）。

4. **不通过时回退**（对接 `plugins/harness-core/rules/开发流程规范.md §2.1` · FE 信号）：
   - `total_tests == 0` → 阶段5（单测编写）；
   - 语法/导入错误、`vitest` 收集失败、`npm install` 失败 → 阶段3（编码实现）。

## 5. 产出物

- `../../changes/<变更目录>/ci_result/ci_result.md`（含真数 · 阶段8 全量复跑取绝对数，禁伪造计数）。

## 6. 完成判据（必须全真，禁止只看 status）

- 门禁判定的**权威可执行单源** = `.harness/scripts/eval_gate_contract.sh`，编码冻结判定式 **`exit==0 && total>0 && passed==total`**（跨 profile 恒等 · BL-INV-1）。三条件按 exit-based 权威表述：
  - `exit == 0`（进程退出码）
  - `total_tests > 0`
  - `passed == total_tests`
- 三者同时满足方视为门禁通过；`ci_result.md` 已落盘。
- **`status` 注**：解析器 `status == SUCCESS` 是 `outputParser()` 对 stdout 的**栈侧布尔投影**（API-BL-3 保证解析失败=FAILURE），**仅供 `ci_result.md` 人读，门禁裁决以判定器 exit-based 为权威**。登记接缝——`exit≠0` 而 stdout 全通过（如覆盖率阈值未达等退出码非 0 但无失败用例）时**以判定器判 FAIL 为准**。
- **跨 profile 恒等机制**：各 profile 的 `outputParser()` 输出 schema 恒同（`{exit, total, passed}` 三元组），统一喂入 `eval_gate_contract.sh`，判定跨 profile 恒等（BL-INV-1）。
- **纯文档卡 N/A 分支**：本卡若为纯文档卡（无可运行 vitest 测试，`total` 天然不可 >0，见 `plugins/harness-core/rules/开发流程规范.md §2.2 ①`），门禁判 N/A，须在 `ci_result.md` 附替代正向证据（人工复核留痕/文档自洽核对），**不触发阶段5 回退**。

## 7. 引用

- 栈无关骨架（不复制 · 指回）：`plugins/harness-core/skills/unit-test-ci/`（三条件门禁判定 + 采集 + 回退路由 + §6 完成判据引用判定器）。
- 绑定声明：`react-vite-binding.md`（实体未迁入 plugin · 待补 · 受控前向引用，见 fe-coding-skill §3；`testCommand()` / `outputParser()` / GateContract 引用恒等）。
- 测试根/命名约定：`plugins/harness-core/rules/项目编码规范.md §4 FE-5`（测试文件位置参考）。
- 输出解析器：`.harness/scripts/parse_vitest_summary.sh`（RM-129 产物 · 引用对象 · 不重写不搬移）。
- 判定器：`.harness/scripts/eval_gate_contract.sh`（RM-129 产物 · 冻结判定式权威单源 · C-5 / BL-INV-1）。
- 模板：`plugins/harness-core/_template/_TEMPLATE/ci_result/ci_result.md`；门禁：`plugins/harness-core/rules/开发流程规范.md`（DF-002 / DF-009）。
