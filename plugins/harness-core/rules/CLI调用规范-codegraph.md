---
name: CLI 调用规范（codegraph 模块）
scope: codegraph 模块 `bin/cg` 七命令面的 CLI 参数面 / 退出码语义 / `--json` 出口 / 仓库根直接执行约定 / 旁路证据非裁决 / 安全约束
rule_kind: 新增模块专属 Rule（本模块 API 设计规范等价物 · 并列补充既有 HTTP API 设计规范 + doc-wiki CLI 调用规范，无覆盖、无冲突）
enforce: mechanical+manual
version: 1.0.0
updated: 2026-06-16
adr: ADR-001（CLI 参数面 + 退出码语义 + `--json` 为契约载体，非 HTTP/OpenAPI）· ADR-005（旁路证据非裁决）
---

# 规则 · CLI 调用规范（codegraph 模块 · 本模块 API 设计规范等价物 · 新增）

> **本规则 = M3.3 完成判据要求的"API 设计规范"在 CLI 工具的适配体**。本模块 = headless Skill-over-CLI 组件（无 HTTP 面 · ADR-001），其"API 设计规范"等价物 = **CLI 调用规范**（`bin/cg` 七命令面的命令行参数 + 退出码语义 + `--json` 出口 + 仓库根直接执行约定 + 旁路证据非裁决纪律）。
> **三套契约面并列声明**：myharness 既有面向 HTTP/FastAPI 的 API 设计规范（`docs/stage-02-全生命周期拓展/03-质量与改进/03-API 设计规范.md`）+ doc-wiki `CLI调用规范.md`（wiki 4 bin）+ 本规范（codegraph 七命令）= **三套并列、各管各的契约面，无覆盖、无冲突**（HTTP 端点 / wiki 4 bin / codegraph 七命令）。
> **声明 · 现役生效**：本规范现役生效，约束 codegraph 模块 `bin/cg` 命令面的 CLI 契约与编排方调用纪律；既有 HTTP API 设计规范不受本规范影响。
> **承接 ADR**：ADR-001（CLI+退出码+`--json` 为契约载体）· ADR-005（旁路证据非裁决）。真值源 = 组件实 `bin/cg`（M3.2 api-design.md §2~§4 逐字校准）。

## 0. 适用范围

适用于 codegraph 模块 `bin/cg` 命令面（七查询命令 `status/query/callers/callees/impact/files/affected` + 索引/配置命令 `init/sync/index --force` + 自检/注册 `doctor/install-skill`）的 CLI 契约约束与编排方调用纪律。不适用于 HTTP/FastAPI 服务（走既有 API 设计规范）、不适用于 wiki 4 bin（走 doc-wiki CLI 调用规范）。

## 1. CLI 契约总则

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CGCLI-001 | 全部命令**在仓库根直接执行**（`bin/cg` 有执行位 · 经注册符号链接 skill 调用时由 `@@CG_BIN@@` 注入绝对路径）；命令在 `$CG_PROJECT` 内执行（`cd "$CG_PROJECT" && ...`）| MUST 机械 | 仓库根直接执行 exit 0 / 退出码断言 |
| CGCLI-002 | **stdout 纯 JSON、诊断/歧义护栏走 stderr**——编排方解析结果只读 stdout `--json`，诊断信息读 stderr，互不混淆（`bin/cg`「stdout stays pure JSON」+ 各查询 case `2>/dev/null` 吞引擎噪声）| MUST 机械 | stdout/stderr 分离核对 |
| CGCLI-003 | **退出码为权威错误判定**（无头会话自述不可信 · C-005）；统一退出码语义见 §2 | MUST 机械+人工 | 退出码断言 |
| CGCLI-004 | 七查询命令**统一 `--json` 出口**（结构化、可 shell 断言 `filePath:line`）；入参差异须区分——`callers/callees/query` 用 `--limit N`，**`impact` 用 `--depth N`（不是 `--limit`）**，`affected` 接 `<files...>` 或 `--stdin` | MUST 人工 | 入参面核对（impact 用 --depth 不误用 --limit）|

## 2. 统一退出码语义（逐字校准 `bin/cg` · cross-cutting-error.md §1）

| 退出码 | 符号名 | 语义 | 触发命令 | 处理 |
|---|---|---|---|---|
| **0** | OK | 命令成功（invoke 正常返回）| 全部 | — |
| **10** | RUNTIME_MISSING | `need_runtime()` 失败（无 `codegraph` on PATH 且无有效 `CODEGRAPH_DIST`）| 所有需运行时命令（status/查询面/init/sync/index）| **优雅降级**：`cg doctor` 显 `runtime: NONE` · 装 bundle/配 cg.env · **不阻塞主流程**（S-007）|
| **11** | NOT_INITIALIZED | `is_initialized()` 失败（`$CG_PROJECT/.codegraph` 不存在）| callers/callees/impact/query/affected/files（status/init 不触发）| 提示 `cg init`（stderr 含「run: cg init」）· 不阻塞 |
| **13** | CG_CLI_ERROR | invoke 引擎非 0 退出 / install-skill 模板缺失 | 各命令 `\|\| die 13` | 看 stderr（引擎错透传）· **查询失败回退 grep**（CG-Q3）|
| **2** | usage error | `cmd` 空 / install-skill `<target>` 非目录 | 全部 | 看 usage · 不阻塞 |

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CGCLI-005 | 编排方据退出码处置：exit 10 → 装运行时 / `cg doctor` 显 `runtime: NONE`（不阻塞）；exit 11 → `cg init`；exit 13 → 看 stderr 引擎错 + 查询失败回退 grep；exit 2 → 修正用法 | MUST 人工 | 退出码处置核对 |
| CGCLI-006 | **全错误码非阻塞铁律**：codegraph 是旁路工具（ADR-005），任一非 0 码**不阻断主流程交付**（与门禁判定式无关）；退出码是确定性诊断信号（CI 降级实测锚点：`cg doctor` runtime NONE → 查询退出码 10 · S-009）| MUST 人工 | CI 降级实测断言（无运行时用例 skip 不计入 total_tests）|

## 3. 各命令参数面契约（校准自 M3.2 api-design.md §2~§3）

> 仅登记契约面要点（完整逐命令 `--json` schema 见 m3.2 api-design.md §2，本规范不复制全表，避免双源漂移）。

| 命令 | 契约面要点 | 锚点 |
|---|---|---|
| `cg query <name>` | 符号定义查询（前置消歧入口）；`--limit N`；`--json` 返同名定义清单 `[{name,filePath,line,kind,language}]`（每条带 `filePath:line` 唯一钉定义）| api-design §2.1 |
| `cg callers/callees <name>` | 调用关系（入边/出边）；`--limit N`；`--json` 带 `edgeKind`；重名时 stderr 歧义护栏 `⚠ N symbols named`（`CG_NO_HINT=1` 可关 · 默认开）| api-design §2.2 |
| `cg impact <name>` | 改动影响面；**`--depth N`（非 `--limit`）**；`--json` 带 `depth` 层级；排除 `contains` 边 | api-design §2.3 |
| `cg files` | 项目结构浏览（tree/flat/grouped）；`--json` 结构化文件清单 | api-design §2.4 |
| `cg affected <files...>` | 改动驱动影响分析；`<files...>` 或 `--stdin`（典型 `git diff --name-only \| cg affected --stdin`）；返受影响测试文件清单 | api-design §2.5 |
| `cg status` | 健康/统计可观测；`--json` 返 `{nodeCount,edgeCount,languages,pendingChanges}`；`pendingChanges≠0` = 索引可能过期判据 | api-design §2.6 |
| `cg init/sync/index --force` | 索引生命周期（init 建库 / sync 增量 / index --force 全量重建）；文本输出非 JSON；退出码 0/10/13 | api-design §3.2 |
| `cg doctor` | 运行时+索引自检（无需运行时/init）；两行文本 `runtime:` + `index:`；`runtime: NONE` 不阻塞 | api-design §3.3 |
| `cg install-skill <target>` | 注册（纯文件拷贝 + `@@CG_BIN@@` → 绝对路径）；exit 0/2/13；**不用** CodeGraph 官方 `install`、**禁手拷烤死绝对路径的旧 SKILL.md 副本** | api-design §3.4 |

## 4. 旁路证据非裁决纪律（契约不被门禁消费 · ADR-005 铁律）

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CGCLI-007 | 本规范的所有 CLI 契约（`--json` 出口、退出码、`pendingChanges`、歧义护栏）= **旁路证据**，**不出现在任一阶段门禁判定式中、不替换/不夺既有门禁裁决权**（ADR-005 · 与 doc-wiki 同型旁路定位）| MUST 人工 | 门禁判定式无 cg 契约消费核对 |
| CGCLI-008 | `cg sync` = **维护副作用非门禁判定**（只刷索引不裁决 · 见 `codegraph查询路由与精度规范.md` CG-S2）；查询输出是"线索"非"结论"（按名寻址高估 · R-007），须经精度纪律兜底，**不得把单次输出当裁决依据** | MUST 人工 | 旁路边界对照检查 |
| CGCLI-009 | 候选焊接点（R-014：ES-001/002 依赖方向校验自动调 cg / 阶段4 评审强制 cg 取证 / 模块二 Index&Map 代码导航）**本轮只登记不焊接**（O-001 · 改门禁判定式面大且违 ADR-005 旁路本意）| MUST 人工 | 焊接点未焊接核对 |

## 5. 安全约束（对齐既有 R-005/CODE-005 + R-012）

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CGCLI-010 | 索引产物 `.codegraph/` + 本机配置 `cg.env`（含 `CODEGRAPH_DIST`/`CODEGRAPH_NODE`/`CG_PROJECT` · 本机绝对路径）**一律 gitignore 不入库**（R-012 · 与 ADR-002 协同）；组件"只加不改"宿主既有跟踪文件、git diff 可审计 | MUST 机械 | gitignore 两条核对 + git diff 仅新增 |
| CGCLI-011 | **不用** CodeGraph 官方 `install`/`uninstall` 改写外部 Agent 配置/权限白名单（ADR-001 · 移植清单 §5）；注册走 `install-skill` 纯文件拷贝 | MUST 人工 | 评审（注册形态核对）|

## 6. 与既有 / doc-wiki 契约面的边界声明（三套并列不冲突）

| 维度 | 既有 HTTP API 设计规范 | doc-wiki CLI 调用规范 | 本 codegraph CLI 调用规范 |
|---|---|---|---|
| 契约面 | HTTP 端点 / REST / OpenAPI yaml | wiki 4 bin 参数面 + 退出码 0/1/2/5/6 | cg 七命令 + 退出码 0/10/11/13/2 + `--json` |
| 校验工具 | schemathesis / swagger | shell 退出码断言 | shell 退出码 + `--json` 断言（ADR-001）|
| 适用对象 | FastAPI 业务服务（demo/harnessdemo）| 文档 wiki 组件 4 bin | 代码图谱组件 `bin/cg` |
| 关系 | 基准 | **并列补充** | **并列补充**（无覆盖 · 无冲突 · ADR-001）|

## 7. 例外与豁免

- 本规范为模块专属新增 Rule，与既有 API 设计规范 + doc-wiki CLI 调用规范三套并列；任何偏离须在卡收尾 `summary.md` 例外区登记理由与影响面。
