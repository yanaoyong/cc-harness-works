---
name: unit-test-ci
trigger: 阶段8 CI 验证
inputs: 已推送代码、阶段5/6 单测产出
outputs: ci_result/ci_result.md
version: 1.2.0
updated: 2026-06-11
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: vendor-neutral（具体栈见 HARNESS_CONFIG.yaml）
---

# Skill · CI 验证（unit-test-ci）

## 1. 目的

在代码推送后执行测试验证，并以**可程序化判定**的三条件门禁填写 `ci_result.md`，避免「状态 SUCCESS 但用例数为 0」的误判。具体测试命令 / 依赖装配 / 输出解析均由**绑定层 StackProfile**（`testCommand()` / `outputParser()`）给出栈无关签名，本 skill 只消费抽象签名、零栈特定串（API-BL-4）。

## 2. 触发条件

进入 **阶段8**（阶段7 推送成功）时由编排中枢加载。

## 3. 输入

- 本次变更的 git 提交 / 分支；
- 阶段5/6 单测报告与用例清单；
- 业务子项目路径（对比测试 **A 轮** 默认 **`harnessdemo/price-service/`**；一般业务仓以 `spec.md` 或 Owner 指定为准）。

## 4. 步骤（SOP）

1. **依赖装配 + 执行测试**：

   - 先执行绑定层栈无关「依赖装配」步骤（本项目实值见 `HARNESS_CONFIG.yaml` 与 `项目编码规范.md §3 PY`）。
   - 再执行绑定层 `testCommand()` 给出的等价测试命令（本项目实值见 `HARNESS_CONFIG.yaml` `test_command`），在目标业务子项目目录下运行。

   > 测试路径以 `spec.md` 或 Owner 指定为准；按变更影响面选择测试路径（工具链改动须含对应工具测试目录）；禁止未执行测试即填 SUCCESS。

   **脚本化执行（`.harness/scripts/stage8_ci.sh` · proposal-012 §3④ · ADR-005 语义不变）**：以上「testCommand 执行 → outputParser 解析 → 冻结判定器裁决」三段串联，日常经由该脚本一条命令端到端跑通——`bash .harness/scripts/stage8_ci.sh [--card <变更目录>]`，自动读取 `HARNESS_CONFIG.yaml` 的 `test_command`、按技术栈标识**映射到对应的 outputParser**（映射表由脚本按配置解析，栈专属解析器由 profile 层提供），并把结果喂给 `eval_gate_contract.sh` 得到 `gate=PASS|FAIL`，同时生成本步骤 2/3 所需的 `ci_result.md` 机械段。脚本只是执行载体，不复制/不旁路判定式；红路归因仍留 Owner 人工填写。**看结果的纪律：用解析器管道看结果、不看裸测试输出全文**——消费脚本 stderr 打印的 `status=`/`total_tests=`/`passed=`/`gate=` 结构化行与 `ci_result.md` 机械段即可判断门禁结论，仅 `gate=FAIL` 时才需要查看脚本输出的 exact 失败用例清单定位问题，不要求通读原始测试输出全文（噪声大、token 贵）。

2. **采集指标**（写入 `ci_result.md`）：

   | 字段 | 取值说明 |
   |---|---|
   | `status` | 退出码 0 → `SUCCESS`；非 0 → `FAILURE` |
   | `total_tests` | 由绑定层 `outputParser(rawStdout, exitCode)` 从原始测试输出还原（`{exit, total, passed}` 三元组之 `total`）；**解析失败须显式报错、不静默置 0**（API-BL-3） |
   | `passed` | 通过数（三元组之 `passed`）；须满足 `passed == total_tests` 且 `total_tests > 0` |

   将 `testCommand()` 的原始 stdout 与退出码喂入绑定层 `outputParser`，输出 `status=` / `total_tests=` / `passed=` 供填入 `ci_result.md`（实参映射见 `HARNESS_CONFIG.yaml` · API-BL-2/3）。

3. 按模板填写三条件表与结论（见 `../../_template/_TEMPLATE/ci_result/ci_result.md`）。

4. **不通过时回退**（对接 `开发流程规范.md` §2.1）：
   - `total_tests == 0` → 阶段 5；
   - 语法/导入/测试收集失败、依赖装配失败 → 阶段 3。

## 5. 产出物

- `../../changes/<变更目录>/ci_result/ci_result.md`

## 6. 完成判据（必须全真，禁止只看 status）

- 门禁判定的**权威可执行单源** = `.harness/scripts/eval_gate_contract.sh`，编码冻结判定式 **`exit==0 && total>0 && passed==total`**（跨 profile 恒等 · BL-INV-1）。三条件按 exit-based 权威表述：
  - `exit == 0`（进程退出码）
  - `total_tests > 0`
  - `passed == total_tests`
- 三者同时满足方视为门禁通过；`ci_result.md` 已落盘。
- **`status` 注**：解析器 `status == SUCCESS` 是绑定层 `outputParser()` 对 stdout 的**栈侧布尔投影**（API-BL-3 保证解析失败=FAILURE），**仅供 `ci_result.md` 人读，门禁裁决以判定器 exit-based 为权威**。登记接缝——`exit≠0` 而 stdout 全通过（如覆盖率阈值未达等退出码非 0 但无失败用例）时**以判定器判 FAIL 为准**。
- 各 profile 的绑定层 `outputParser()` 实例输出 schema 恒同、同喂 `eval_gate_contract.sh`（判定跨 profile 恒等 · BL-INV-1）；各栈实值见 `HARNESS_CONFIG.yaml`。

## 7. 引用

- 模板：`../../_template/_TEMPLATE/ci_result/ci_result.md`
- 上游：`../unit-test-write/`（阶段5）
- 门禁：`docs/stage-01-Harness体系建设/03-质量与改进/08-质量门禁与反馈回路规范.md`、`docs/stage-01-Harness体系建设/02-体系设计/07-十阶段流程详细规范.md` 阶段8
- 规则：`../../rules/开发流程规范.md`（DF-002、DF-009）
- 选型：`docs/stage-01-Harness体系建设/05-技术栈与工具/14-附录-Step0-技术选型确认记录.md`
