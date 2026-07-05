# modules/codegraph — CodeGraph 接入适配层（Skill-over-CLI, v1）

把开源 [CodeGraph](https://github.com/colbymchenry/codegraph) 作为**编码 Agent 的代码理解后端**接入，形态为 **Skill-over-CLI**：一份 skill 教 Agent 何时/如何调用 CodeGraph CLI，一个薄包装脚本归一运行时与输出。

> 设计依据：ADR-001 接入策略决策、模块设计（上游研究档案未随组件迁移）。
> 可行性实证：Stage 2 Spike 日志（上游研究档案未随组件迁移）。

## 前置依赖 / Prerequisites

**codegraph 引擎是外部前置依赖，本组件不含引擎本体。** 迁入本仓库的是**接入适配层**（`bin/cg` 薄包装 + skill 模板 + 测试 + 文档）；真正做索引/查询的引擎是开源 [CodeGraph](https://github.com/colbymchenry/codegraph)，须**单独安装**才能用查询面。装引擎是手动、可控、零外部副作用的——本组件**不**自动安装引擎、**不**改写你的 Agent 配置/权限白名单（接入策略，ADR-001）。

**两种安装方式（二选一）：**

- **生产**（官方 bundle，自带 Node runtime，无版本要求）：
  ```sh
  curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh
  ```
  让 `codegraph` 上 PATH。
- **开发**（源码 dist）：`cp bin/cg.env.example bin/cg.env`，填 `CODEGRAPH_DIST`（dist/bin/codegraph.js）+ `CODEGRAPH_NODE`（Node ≥ 22.5，如 `npx -y node@22`）。

**就绪自检**：`bin/cg doctor` —— 显示 `runtime: NONE` 即引擎未就绪。

**降级语义**：无引擎时 `cg` 优雅降级——查询面（`query`/`callers`/`callees`/`impact`/`affected`/`files`）退出码 `10`（RUNTIME_MISSING）、功能不可用，但 `doctor`/`install-skill` 仍可用。codegraph 是**旁路查询工具、不进任一阶段门禁**（ADR-005），引擎缺位不阻断主流程，只是查询面用不上。

**opt-in 显式授权例外**：经 `/harness-core:bootstrap` 一键（安装前展示动作、用户确认后执行）或 `HARNESS_AUTO_BOOTSTRAP=1` / config 开关（开关本身即用户显式授权）可自动安装引擎——两者均为用户显式授权、带 sha256 校验（fail-closed，校验失败拒绝执行），**仍非静默默认**（默认静默全自动已否决）；详见 [ADR-014](../../../../.harness/changes/feat-plugin-bootstrap-automation-20260705/coding/adr/ADR-014-optin-engine-install-exception.md)。

> 操作手册见 **[USAGE.md](USAGE.md)** §1。下方「## 安装」是含 skill 安装/建索引的完整接入流程，引擎前置依赖的"是什么/为什么必须"以本段为权威声明。

## 结构

```
modules/codegraph/
├── bin/
│   ├── cg              # 适配脚本：runtime 选择 / 项目路径 / init 检查 / JSON 归一 / 退出码 / 歧义提示
│   ├── cg.env.example  # 配置样例（拷成 cg.env 使用；cg.env 已 gitignore）
│   └── cg.env          # 本机配置（不入库）
├── skill/
│   └── SKILL.md        # skill 模板（真源；install-skill 即拷到 .claude/skills/codegraph/）
├── test/
│   └── cg_test.sh      # 适配层回归测试（退出码 + 歧义提示 + install-skill + JSON 纯净，10 项）
├── USAGE.md            # 使用手册（接入步骤 / 日常命令 / 坑 / 退出码）
└── README.md
```

## 歧义提示（适配层硬化）

`cg callers/callees/impact <name>` 在该名字有 >1 个定义时，会向 **stderr** 打印
`cg: ⚠ N symbols named "<name>" …`，提醒结果是同名并集、可能假阳性（stdout 仍是纯 JSON）。
把 Stage 1/PoC 的精度纪律从 skill 文本前移到工具输出，降低 Agent 漏看的概率。
用 `CG_NO_HINT=1` 可关闭。依据：精度评测（nest 上 68% 符号撞名 · 上游研究档案未随组件迁移）。

测试：`sh modules/codegraph/test/cg_test.sh`（运行时不可用时自动跳过运行时相关用例，不会误失败）。

## 安装（手动、可控、零外部副作用）

```sh
# 1) runtime：先装外部引擎（见上方「## 前置依赖 / Prerequisites」段；生产 bundle 或开发 dist 二选一）
# 2) 安装 skill 到目标仓库（纯拷贝，不需要 runtime）
bin/cg install-skill /path/to/target-repo
# 3) 建索引
CG_PROJECT=/path/to/target-repo bin/cg init
# 4) cg doctor 自检；在 Agent 里问「谁调用了 X」验证 skill 触发
```

完整操作见 **[USAGE.md](USAGE.md)**。不使用 CodeGraph 官方 `install`——避免改写外部 Agent 配置/权限白名单。

## `cg` 命令

`doctor`（自检，无需 runtime）/ `install-skill <target>`（装 skill，无需 runtime）/
`init` / `sync` / `status` / `query <name>` / `callers <name>` / `callees <name>` /
`impact <name>`（`--depth`）/ `affected <file...>`（`--stdin`）/ `files`。
除 `doctor`/`install-skill`/`init`/`sync` 外均输出 JSON。退出码：`10` 无 runtime、`11` 未初始化、`13` CLI 错误、`2` 用法。

## 已知精度边界（写进了 SKILL.md）

callers/callees/impact **按符号名寻址**，重名/重载会合并上报——用前先 `cg query <name>`
看是否有多个同名定义，再按 `filePath` 核对。详见 Stage 1 §6（上游研究档案未随组件迁移）。
