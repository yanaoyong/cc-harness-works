# CodeGraph 接入使用手册（cg, Skill-over-CLI v1）

面向把本模块接入到一个**目标仓库**、让编码 Agent 用上代码图谱的操作者。
设计依据 ADR-001，能力边界见精度评测（上游研究档案未随组件迁移）。

## 1. 准备运行时（二选一）

> **前置警示**：codegraph 引擎是**外部前置依赖**，没有它则查询面**降级、不可用**——`bin/cg doctor` 会显示 `runtime: NONE`，`query`/`callers`/`callees`/`impact`/`affected`/`files` 退出码 `10`（RUNTIME_MISSING）。**先按下表装好引擎**再往下走（§2 接入）。"是什么/为什么必须"见组件 [README.md](README.md) §「前置依赖 / Prerequisites」。

| 方式 | 步骤 | 适用 |
|---|---|---|
| **生产**：官方 bundle | `curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh \| sh`，让 `codegraph` 上 PATH | 推荐——自带 Node runtime，无版本要求 |
| **开发**：源码 dist | `cp bin/cg.env.example bin/cg.env`，填 `CODEGRAPH_DIST`（dist/bin/codegraph.js）+ `CODEGRAPH_NODE`（Node≥22.5，如 `npx -y node@22`） | 本仓库开发/调试 |

自检：`bin/cg doctor` —— 显示 runtime 与索引状态（无 runtime 也能跑，会提示 `runtime: NONE`）。

## 2. 接入一个目标仓库（三步）

```sh
# 1) 安装 skill 到目标仓库（纯文件拷贝，不需要 runtime）
bin/cg install-skill /path/to/target-repo

# 2) 在目标仓库建索引
CG_PROJECT=/path/to/target-repo bin/cg init     # 或 cd 进去再 cg init

# 3) 用 Agent 打开目标仓库，问一个结构性问题验证 skill 触发
#    例：「谁调用了 <某函数>？」看它是否走 cg
```

> `install-skill` 把 `skill/SKILL.md` 拷到 `<target>/.claude/skills/codegraph/SKILL.md`。
> **不**使用 CodeGraph 官方 `install`——避免改写外部 Agent 配置/权限。

## 3. 日常命令（均输出 JSON，`doctor`/`init`/`sync` 除外）

```sh
cg doctor                 # runtime + 索引状态自检
cg status                 # 统计/健康（nodeCount/edgeCount/languages/pendingChanges）
cg query <name>           # 找符号
cg callers <name>         # 谁调用（--limit N）
cg callees <name>         # 调用了谁（--limit N）
cg impact  <name>         # 改动影响面（--depth N，注意不是 --limit）
cg files                  # 项目结构
cg affected <files...>    # 受改动源文件影响的测试文件（--stdin 读文件列表）
cg sync                   # 改完代码后增量同步
```

CI / 改动影响测试，可接 git diff：

```sh
git diff --name-only origin/main... | cg affected --stdin
```

## 4. 两个必须知道的坑

1. **按名寻址会高估**（精度）：`callers/callees/impact` 把所有同名定义的关系**合并**。
   `cg` 已内置护栏——名字有 >1 个定义时向 **stderr** 打印 `⚠ N symbols named "<name>" …`。
   **看到该警告**：先 `cg query <name>` 看清各定义 `filePath:line`，只采信同模块的结果。
   关掉护栏：`CG_NO_HINT=1`。背景：nest 上 68% 可调用符号撞名。
2. **索引新鲜度**（staleness）：结果取决于索引是否同步。改完代码先 `cg sync`。
   注意 CodeGraph 用 git 状态做变更检测——**`git checkout` 切分支后** git 判文件「干净」，
   `pendingChanges` 可能漏报，此时显式 `cg sync` 或 `cg index --force`。

## 5. 退出码（适配层契约）

| 码 | 含义 | 处理 |
|---|---|---|
| 0 | 成功 | —— |
| 10 | RUNTIME_MISSING | 装官方 bundle 或配 `cg.env` |
| 11 | NOT_INITIALIZED | `cg init` |
| 13 | CG_CLI_ERROR | 看 stderr |
| 2 | 用法错误 | 看 usage |

## 6. 自测

```sh
sh modules/codegraph/test/cg_test.sh     # 退出码 + 歧义提示 + JSON 纯净（10 项）
```
运行时不可用时，运行时相关用例自动跳过、不误失败。
