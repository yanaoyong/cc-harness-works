# cc-harness-works

Harness 全生命周期方法论的 Claude Code 插件市场：一套栈无关的 10 阶段 K 流程 + 元流程 M0–M5 骨架，外加可选的栈 profile（Python / React+Vite）。

## Portable 文档

仓库内新增一套可离线分发的 Harness portable handbook，放在 [`docs/portable-handbook-20260708/`](docs/portable-handbook-20260708/)。

这 25 篇文章来自项目 wiki 与实践沉淀，但正文已经改写为自足版本：不依赖 wiki 链接即可理解概念、流程、角色、质量门禁、运行时集成与分发维护方式。适合随插件市场、培训材料、项目初始化包或离线文档站一起使用。

| 范围 | 内容 |
|---|---|
| 00–04 入门与主流程 | [阅读路线与术语地图](docs/portable-handbook-20260708/00-阅读路线与术语地图.md)、[Harness 是什么与适用场景](docs/portable-handbook-20260708/01-Harness是什么与适用场景.md)、[项目制品与路径语境](docs/portable-handbook-20260708/02-项目制品与路径语境.md)、[最小工作流](docs/portable-handbook-20260708/03-最小工作流-从一次请求到一张变更卡.md)、[十阶段主流程](docs/portable-handbook-20260708/04-十阶段主流程.md) |
| 05–09 编排机制 | [Application Owner 与角色编排](docs/portable-handbook-20260708/05-Application-Owner与角色编排.md)、[子 Agent 委派与防漂移纪律](docs/portable-handbook-20260708/06-子Agent委派与防漂移纪律.md)、[Rules 体系与常驻约束](docs/portable-handbook-20260708/07-Rules体系与常驻约束.md)、[Skills 体系与阶段触发](docs/portable-handbook-20260708/08-Skills体系与阶段触发.md)、[变更卡与持久化记忆](docs/portable-handbook-20260708/09-变更卡与持久化记忆.md) |
| 10–14 元流程 | [元流程总览 M0 到 M5](docs/portable-handbook-20260708/10-元流程总览-M0到M5.md)、[M0-M2 愿景需求范围](docs/portable-handbook-20260708/11-M0-M2-愿景需求范围.md)、[M3 架构接口 ADR 与定制规则](docs/portable-handbook-20260708/12-M3-架构接口ADR与定制规则.md)、[M4-M5 工程基线与 Roadmap](docs/portable-handbook-20260708/13-M4-M5-工程基线与Roadmap.md)、[双轨启动与模式 E 级联评估](docs/portable-handbook-20260708/14-双轨启动与模式E级联评估.md) |
| 15–19 知识层与旁路 | [知识层总览](docs/portable-handbook-20260708/15-知识层总览-wiki-codegraph-M05.md)、[wiki-engine 与 wiki-query 使用纪律](docs/portable-handbook-20260708/16-wiki-engine与wiki-query使用纪律.md)、[wiki 摄取、新鲜度、信任边界与采纳度重构](docs/portable-handbook-20260708/17-wiki摄取新鲜度信任边界与采纳度重构.md)、[codegraph 使用边界与查询路由](docs/portable-handbook-20260708/18-codegraph使用边界与查询路由.md)、[L 旁路通道与旁路证据哲学](docs/portable-handbook-20260708/19-L旁路通道与旁路证据哲学.md) |
| 20–24 质量、运行时、分发与维护 | [质量门禁证据体系与行为验收](docs/portable-handbook-20260708/20-质量门禁证据体系与行为验收.md)、[测试守护、契约测试与假绿治理](docs/portable-handbook-20260708/21-测试守护契约测试与假绿治理.md)、[Claude Code 桥接、hooks 与运行时集成](docs/portable-handbook-20260708/22-ClaudeCode桥接hooks与运行时集成.md)、[插件化分发、模板导出与可移植性](docs/portable-handbook-20260708/23-插件化分发模板导出与可移植性.md)、[决策史、失败案例、近期 ADR 与维护手册](docs/portable-handbook-20260708/24-决策史失败案例近期ADR与维护手册.md) |

## 安装

```
/plugin marketplace add yanaoyong/cc-harness-works
/plugin install harness-core@cc-harness-works
```

## 插件清单

| 插件 | 说明 |
|---|---|
| `harness-core` | Harness 核心方法论骨架（栈无关）：10 阶段 K 流程 + 元流程 M0–M5、5 角色 agent、流程层 skill、旁路组件（codegraph / wiki-engine）。 |
| `harness-profile-python` | Python 栈 profile：FastAPI/pytest/ruff 编码·评审·测试 skill + 栈绑定层。依赖 `harness-core`。 |
| `harness-profile-react-vite` | React+Vite+TypeScript FE 栈 profile：FE 编码·评审·测试 skill 套件 + 栈绑定层。依赖 `harness-core`。 |

栈 profile 按需安装，例如：

```
/plugin install harness-profile-python@cc-harness-works
```
```
/plugin install harness-profile-react-vite@cc-harness-works
```

## 首次使用 · 建完就核验

安装 + 首次会话后，harness 会自动落骨架并尝试建 CodeGraph 索引 / wiki 骨架。但**骨架建好 ≠ 能查询**，装完请主动核验一次：

```
cg doctor       # 看引擎运行时（runtime）是否就绪
cg status       # 看索引（index）与 pendingChanges
ls wiki/        # 看 wiki 是否已摄取内容（只有骨架时基本为空）
```

### 坑① · CodeGraph 索引已建但缺运行时

`cg doctor` 显示 `index: initialized` 但 `runtime: NONE` → 引擎运行时没装成 / 丢失。此时 `cg` 查询返回退出码 10（RUNTIME_MISSING），会降级回退 grep——不阻断会话，但查不到符号级结果。

补救：重跑一键就绪命令（全步骤幂等，可反复补装）：

```
/harness-core:bootstrap
```

### 坑② · wiki 只有骨架无内容

bootstrap 只落 wiki **骨架**，不做内容摄取。摄取需先注入 API key（走环境变量，**切勿写入任何文件 / 提交入库**）：

```
export DEEPSEEK_API_KEY=...   # 仅环境变量，勿落盘
```

然后按 `wiki-engine` SKILL.md 的批循环工作流增量摄取。

### 坑③ · 第二个项目没自动 bootstrap

自动 bootstrap 语义是「**仅第一次 · 每项目一次**」——每个项目各自独立触发。若想关闭自动行为，任选其一：

```
export HARNESS_AUTO_BOOTSTRAP=0        # 环境变量逃生阀
# 或在 HARNESS_CONFIG.yaml 写：
#   bootstrap.auto: false
```

需要手动补跑时随时执行 `/harness-core:bootstrap`（幂等）。

> 说明：v0.6.1 起，bootstrap 状态哨兵已按项目隔离（落项目内 `.harness/state/`），修复了旧版「同机全部项目只自动 bootstrap 一次」的问题。

### 存量升级：一次性重 bootstrap（预期，无害）

从旧版（哨兵落全局）升级的项目，因哨兵落点改为项目本地，**首次会话可能重跑一次 bootstrap**。这是一次性迁移副作用，幂等无害（已装好的引擎 / 索引 / wiki 骨架各步骤会自动跳过）。

### 坑④ · wiki 自动摄取直接提交到当前分支致 main 漂移

v0.7.4 起，Stop hook（`session_stop_wiki_autoingest.sh`）在会话结束时后台跑 B2 自动摄取：检测 `wiki/` 源文档 delta → **每批直接 `git commit` 到当前分支、从不 push**。若在一个长期存活的 `main` 检出上反复触发，会不断把摄取批次堆到本地 main（`ahead N`），而 origin/main 又被并行推进 → 本地 main 既膨胀又落后；多个检出对同一批源卡各摄一遍还会产生重复内容。

该 hook 有 opt-in 安全阀（默认关）：仅当 `WIKI_ENGINE_AUTO_INGEST=1` 才摄取。若你把它设在**受追踪的** `.claude/settings.json`（全检出可见），main 检出也会一起摄取。

想要「**main 只做同步、不摄取；分支流程内照常摄取**」，在 **main 检出**建一个 gitignored 的 `.claude/settings.local.json` 覆盖开关（local 优先级高于 settings.json，且不传播到 worktree 分支）：

```json
{ "env": { "WIKI_ENGINE_AUTO_INGEST": "0" } }
```

- Stop hook 用 `git rev-parse --show-toplevel` 自定位到运行所在的检出，故按检出隔离——该覆盖只关 main、不影响分支。
- settings env 在**会话启动时**载入：改后**下个会话起生效**，当前会话结束可能再摄一批。
- 已漂移的 main 用 `git reset --hard origin/main` 拉回即可（被丢弃的提交仍可经 reflog 找回）。

## 插件升级后 · 脚手架怎么更新

升级插件后（`/plugin marketplace update cc-harness-works` + `/reload-plugins`），**大部分脚手架会自动更新**：hooks / commands / workflows / skills / agents / rules 在下个会话由 drift-sync 从新版插件缓存**单向刷新**（你本地改过的镜像文件会被识别为定制、告警跳过、**绝不覆盖你的改动**）。所以规则 / 流程 / 工作流类的修复，升级 + 重载后即自动生效，无需手工干预。

> ⚠️ **重点：引擎组件不随插件升级自动刷新，需手动重跑 bootstrap。**
> `.harness/components/`（codegraph / wiki-engine 的二进制 + 注册脚本）只在**首次** bootstrap 落盘；成功哨兵 `.bootstrap_done` 无版本戳，不会随插件升级自动重跑。**若某次发版更新了引擎组件，请手动执行一次**（全步骤幂等，已就绪的步骤自动跳过）：
>
> ```
> /harness-core:bootstrap
> ```

此外 `_TEMPLATE`（变更卡模板）为 no-clobber——存在即不覆盖。发版若改了模板结构，需手动删除 `.harness/changes/_TEMPLATE`，下个会话会自动从新版补齐。

## 随项目分发插件声明 · /harness-core:pin-to-project

装好插件后，如果你是项目主人、希望**队友克隆仓库即被提示装好同一套插件**（免去每人手工 `/plugin marketplace add` + `/plugin install`），可主动运行：

```
/harness-core:pin-to-project
```

它会把 marketplace（`cc-harness-works`）+ 本项目**已启用插件**的声明 JSON-safe 合并写进 tracked 的 `.claude/settings.json`（保留 `statusLine` 等既有键）。提交入库后，队友克隆并信任仓库时，Claude Code 会提示安装这些插件。

- **opt-in 语义**：仅在你**主动运行**本命令时才写，绝不自动触发、不注册任何 hook。写完记得 `git add .claude/settings.json && git commit` 才会随仓库分发。
- **供应链知情提示**：把该声明写入 tracked 配置并入库 = 任何**克隆并信任本仓库**的人会被 Claude Code 提示安装此 marketplace + 插件——这是你作为项目主人**主动的分发决定**，会影响所有队友，请先 review diff 再提交。
- **版本局限**：声明**只锁「启用哪些插件」，不锁 sha/版本**；克隆者安装的是 marketplace **当前 HEAD 版本**，可能与你本地版本不同。

## 完整指南

分发渠道、双仓同步、认证排障等完整说明见项目分发指南（plugin-distribution-guide）。
