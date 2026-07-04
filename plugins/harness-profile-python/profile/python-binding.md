---
view: stack-profile-binding
profile: harness-profile-python
stack: python
contract: BindingLayerContract（api-design §1 · AGG-1 StackProfile）
version: v1
updated: 2026-06-28
---

# harness-profile-python · Python StackProfile 绑定声明（python-binding）

> 本文件是 `harness-profile-python` 这份 **Python StackProfile** 的绑定声明制品（声明式 · 非可执行代码）。
> 它给出 `BindingLayerContract`（`api-design.md §1` · AGG-1 StackProfile）四成员的 **Python 实值** + 两值对象（StackTag / RequiredCommandRef）+ **引用恒等** GateContract。
> **单源纪律（C-3）**：本声明只**消费/引用**既有契约与承载体（`api-design §1` 契约定义 / `HARNESS_CONFIG.yaml` 命令 / `parse_pytest_summary.sh` 解析器 / `coding-skill/specs/` 分层 spec / `项目编码规范.md §3 PY` 约束），**不重定义契约、不重写/不搬移脚本、不改 manifest**。流程层经抽象签名引用本声明，新增本 profile 核心流程层 0 改动（BL-INV-3 / AR-LY-1）。

---

## 1. 契约成员 · Python 实值（声明式接口表 · 对照 api-design §1.1）

| 成员 | 签名（api-design §1.1）| Python 实值（声明）| 实值来源 / 论证 |
|---|---|---|---|
| **testCommand** | `testCommand(): CommandSpec` | `{ cmd: "pytest", args: ["-q"], cwd: <引用 HARNESS_CONFIG.yaml> }` —— `cwd` **引用** `HARNESS_CONFIG.yaml`（A 轮 `compare_path_a=harnessdemo/price-service/` / B 轮 `compare_path_b=demo/price-service/` / 一般业务仓以 spec 指定业务根为准），**不写死单一路径** | `HARNESS_CONFIG.yaml` `test_command="pytest -q"` + `test_path="tests/"`；对齐 `项目编码规范.md §3 PY-4` 门禁等价命令 |
| **outputParser** | `outputParser(rawStdout, exitCode): {exit,total,passed}` | **引用** `.harness/scripts/parse_pytest_summary.sh`（已存在 · 不重写不搬移）；脚本输出 `{status, total_tests, passed}`，本声明文档化其 → 契约 `{exit, total, passed}` 的维度适配（见 §3） | `parse_pytest_summary.sh`：从 `pytest -q` stdout 解析；无 `passed` 摘要 → `status=FAILURE total_tests=0 passed=0`（显式 FAILURE 非静默置 SUCCESS · 满足 API-BL-3 防假绿） |
| **layeredSpecMapping** | `layeredSpecMapping(): SpecLayer[]` | 映射 8 份后端分层 Spec（层名 + 路径），**引用在原地** `.harness/skills/coding-skill/specs/`（见 §4 表 · 不物理搬移 · OQ-3） | `coding-skill/specs/README.md` 索引（Python 正文已落地） |
| **RequiredCommandRef** | （值对象 · §1.2） | `{ "python": ["python3", "ruff"] }` | 与 manifest `requiredCommands=[python3,ruff]` 集合一致（API-BL-5 无幽灵依赖）；`pytest`/`pip` 视为 python3 生态内运行器（`python3 -m pytest`/`python3 -m pip` 等价）非独立外部命令，与 api-design §1.2 RequiredCommandRef 一致 |
| **StackTag** | （值对象 · §1.2） | `{ "stack": "python" }` | api-design §1.2 身份标签 · S-003 |
| **GateContract** | （值对象 · §1.2 · 跨 profile 恒等） | **引用恒等判定式** `exit == 0 && total > 0 && passed == total` | **引用 api-design §1.2 / API-BL-2 · 不重定义**（C-5 跨 profile 恒等：本 profile 只换 `testCommand`/`outputParser`，判定本体不变 · AR-LY-3） |

---

## 2. 值对象块（内嵌 jsonc · 机读区块）

```jsonc
// ① testCommand() → CommandSpec（Python 实值）
{
  "cmd": "pytest",
  "args": ["-q"],
  // cwd 引用 HARNESS_CONFIG.yaml，不写死单一路径：
  //   A 轮 = compare_path_a (harnessdemo/price-service/)
  //   B 轮 = compare_path_b (demo/price-service/)
  //   一般业务仓 = spec 指定业务根
  "cwd": "<HARNESS_CONFIG.compare_path_a · 不写死>"
}

// ② outputParser() → 引用 .harness/scripts/parse_pytest_summary.sh（不重写/不搬移）
//    脚本输出 {status, total_tests, passed} → 契约 {exit, total, passed} 维度适配见 §3

// ③ layeredSpecMapping() → SpecLayer[]（引用在原地 · 见 §4 表）

// ④ RequiredCommandRef（该栈外部命令依赖）
{ "python": ["python3", "ruff"] }

// ⑤ StackTag（身份标签 · S-003）
{ "stack": "python" }

// ⑥ GateContract（引用 api-design §1.2 / API-BL-2 · 跨 profile 恒等 · 不重定义）
{
  "decision": "exit == 0 && total > 0 && passed == total",
  "invariant": "frozen-across-all-profiles"
}
```

---

## 3. outputParser 维度适配（`{status, total_tests, passed}` → `{exit, total, passed}` · OQ-4 文档化 · 不写可执行薄包装）

> `parse_pytest_summary.sh` 输出 `{status, total_tests, passed}`，而 api-design §1.1 `outputParser` 契约输出 `{exit, total, passed}`；维度名不一字面。本节以**文档声明**承载适配（守"声明式制品非代码" + "不重写/不搬移脚本"），不引入可执行包装层。

**维度映射**

| 脚本字段 | 契约字段 | 关系 |
|---|---|---|
| `total_tests` | `total` | 直接等价（`total = passed + failed + skipped`） |
| `passed` | `passed` | 直接等价（pytest 终端 `N passed` 计数） |
| `status` | （decision 的**非权威布尔投影**） | `status=SUCCESS` ≈ 「`failed==0 && total>0`」口径；`status` **不参与计数比较**、不是判定权威 |

**判定决定权在数值，非 `status` 单条（LOW-2 精修）**

- GateContract 判定式 `exit == 0 && total > 0 && passed == total` **实评在数值 `{total, passed}` 上**；**决定性条件是 `passed == total`（数值）**，`status` 仅承载 decision 通过/不通过的非权威布尔投影。
- 注意 parser 既有行为 `total = passed + failed + skipped`：当 `skipped > 0 && failed == 0` 时 parser 给 `status=SUCCESS`（"failed==0 且 total>0"口径）但 `passed < total`，**单看 `status` 会偏松**；而门禁判定式因**同时强制 `passed == total`** 而**正确判不通过**——故 `status` 偏松**不影响最终判定**，判定式语义跨 profile 恒等（决定权落在 `passed == total` 数值条件 · skipped 用例使门禁不通过是既有正确行为、非 bug）。
- **解析失败路径 = 显式失败非静默置 0**：无 `passed` 摘要（坏/空 stdout）时脚本返回 `status=FAILURE total_tests=0 passed=0`——套 GateContract 因 `total > 0` 为 False 直接判**不通过**，**不会出现 `SUCCESS + total=0` 假绿**（满足 API-BL-3 / BL-INV-1 方向）。

---

## 4. layeredSpecMapping · 8 份后端分层 Spec（引用在原地 · OQ-3 · 不搬移）

| 序 | 层名 | Spec 路径（引用在原地） |
|---|---|---|
| 01 | 表现层 | `.harness/skills/coding-skill/specs/01-api-router.md` |
| 02 | 应用层 | `.harness/skills/coding-skill/specs/02-schemas.md` |
| 03 | 应用层 | `.harness/skills/coding-skill/specs/03-service-contracts.md` |
| 04 | 业务层 | `.harness/skills/coding-skill/specs/04-domain-logic.md` |
| 05 | 数据层 | `.harness/skills/coding-skill/specs/05-schema-migration.md` |
| 06 | 数据层 | `.harness/skills/coding-skill/specs/06-repository.md` |
| 07 | 适配层 | `.harness/skills/coding-skill/specs/07-adapter.md` |
| 08 | 文档层 | `.harness/skills/coding-skill/specs/08-openapi.md` |

> 物理迁入 `plugins/harness-profile-python/` 留 plugin 打包卡 **RM-139**（守 RM-127「不动 specs」承诺）。
>
> 上述 8 条 `.harness/skills/coding-skill/specs/` 路径指向消费方项目本地镜像路径（由 SessionStart hook 按需落盘），非权威本体路径；权威本体位于 `plugins/harness-core/skills/coding-skill/specs/`。

---

## 5. 不变式与守界（引用 · 不重定义）

- **BL-INV-1**：`GateContract.decision` 跨所有 profile 恒等——双向校验见阶段5 守护（喂坏 stdout → 不通过 / 喂真实通过 stdout → 正确还原 `{total,passed}`）。
- **BL-INV-3 / AR-LY-1**：新增本 profile，核心流程层 5 skill SOP **0 改动**（git diff 核心 6 skill 为空 · 阶段4 评审 + 人工核对兜底）。
- **API-BL-3**：outputParser 解析失败显式报错不静默置 0（见 §3 解析失败路径）。
- **API-BL-5 / PM-INV-2**：RequiredCommandRef 与实调命令一致、无幽灵依赖（`python3`/`ruff` · `pytest`/`pip` 为 python3 生态内运行器）。

## 6. 引用

- 契约定义（消费对象 · 不重写）：`project/architecture/fullstack-plugin/m3.2_interface/api-design.md §1` + `plugins/harness-core/rules/API设计规范.md §1`（API-BL-1~5）+ `plugins/harness-core/rules/架构规范.md`（AR-LY-1 / AR-PL-2）。
- 命令实值来源：`HARNESS_CONFIG.yaml`（`test_command` / `test_path` / `compare_path_a` / `compare_path_b`）。
- 输出解析器（引用对象 · 不重写不搬移）：`.harness/scripts/parse_pytest_summary.sh`。
- 分层 Spec 索引：`.harness/skills/coding-skill/specs/README.md`（消费方项目本地镜像路径 —— 指向项目安装后由 hook 落盘的本地副本）。
- 栈特定约束（what）：`plugins/harness-core/rules/项目编码规范.md §3 PY-1~5`；分层（structure）：`plugins/harness-core/rules/工程结构.md §2/§2.1 ES`。
- Python 操作 how（SOP）：`.harness/skills/py-coding-skill/` · `py-code-review/` · `py-unit-test-write/` · `py-unit-test-ci/`（消费方项目本地镜像路径 —— 指向项目安装后由 hook 落盘的本地副本）。
