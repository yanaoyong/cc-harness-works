# Plugin 分发、验证与信任边界指南

> 面向 Harness plugin 的使用者与发布维护者。消费方可离线完成安装后诊断；维护者从源仓的单一分发契约组装公共仓，并把普通检查与发布标签检查隔离。

Harness 包含 `harness-core`、`harness-profile-python` 与 `harness-profile-react-vite`。marketplace 名称是 `cc-harness-works`，安装后缀始终为 `@cc-harness-works`。

## 1. 安装与信任边界

### 本地开发态

```bash
claude --plugin-dir <plugin-dir>
```

### 公共 marketplace

```text
/plugin marketplace add yanaoyong/cc-harness-works
/plugin install harness-core@cc-harness-works
```

按需安装 profile：

```text
/plugin install harness-profile-python@cc-harness-works
/plugin install harness-profile-react-vite@cc-harness-works
```

私有仓也应添加整个 Git 仓库，而不是 `marketplace.json` 的 raw URL；manifest 中的相对 `source` 需要仓库上下文。私有仓凭据应由 Git credential helper、SSH agent 或环境变量提供，不得写入仓库、plugin 文件、日志或示例配置。

第三方 plugin 内容不由 Anthropic 审计。安装或信任仓库前，应审查来源、`.claude-plugin/marketplace.json`、各 plugin manifest、Hooks 与请求的权限。Hook 可在会话生命周期内读取或写入项目/会话状态；“安装到只读缓存”不等于“运行时无项目副作用”。任何网络访问、公开同步、push 或 tag 操作都须由人明确知情并授权。

## 2. 离线验证与只读诊断

以下命令均从源仓根运行。

### 普通分发检查

```bash
python3 .harness/scripts/check_plugin_distribution.py
```

普通模式离线、只读，不要求任何发布标签存在。它执行 root 与逐 plugin strict validation、语法检查、版本 lockstep、profile→core 约束、Hook 目标、manifest/权限等分发契约检查。

### Bootstrap report-only

先定位安装态脚本：

```bash
SCRIPT="${CLAUDE_PLUGIN_ROOT}/hooks/harness_bootstrap.sh"
bash "$SCRIPT" --report-only
```

本仓开发态可用：

```bash
bash plugins/harness-core/hooks/harness_bootstrap.sh --report-only
```

`--report-only` 是零安装、零配置写入、零 `PATH` 修改的只读探测。输出：

```text
engine=ready|missing
index=ready|missing
wiki=ready|missing
command.git=available|degraded
command.python3=available|degraded
command.ruff=available|degraded
command.npx=available|degraded
degraded_policy=missing commands do not block core flows that do not depend on them
```

全部就绪时 exit 0；任一项缺失时 exit 20。`degraded` 只表示依赖该命令的能力不可用，不阻断不依赖它的核心流程。该诊断不会自动安装缺失命令，也不会写配置或修改 `PATH`。

### Codegraph 安装态探针

不要依赖裸 `cg` 是否恰好位于 shell `PATH`。安装态使用 plugin 根下的完整路径：

```bash
"${CLAUDE_PLUGIN_ROOT}/components/codegraph/bin/cg" doctor
"${CLAUDE_PLUGIN_ROOT}/components/codegraph/bin/cg" status
```

本仓开发态对应：

```bash
plugins/harness-core/components/codegraph/bin/cg doctor
plugins/harness-core/components/codegraph/bin/cg status
```

路径不存在或命令返回非零时，保留真实退出码并报告 degraded；不得因此自动安装、改 `PATH` 或隐式联网。

## 3. Hook inventory 与副作用矩阵

[`hooks.json`](../../plugins/harness-core/hooks/hooks.json) 的 `hooks` 对象是 Hook 计数与事件归属的 SSOT，说明文字不是计数源。当前结构化结果是 **17 个 command Hook，其中 SessionStart 8 个**；增删配置后应重新从 JSON 计算，不手改常量。

| Event | 触发与当前行为 | 项目/会话写入 | 启用条件 | 失败降级 | 出站行为 |
|---|---|---|---|---|---|
| `SessionStart` | 会话启动时依序进行脚手架落盘、镜像刷新、常驻契约注入、main 自动同步检测/快进、合并态提示、wiki 新鲜度、statusline 设置与 bootstrap 提示/接力 | 可能写 `.harness/`、`.claude/`、项目本地 state、wiki 骨架/索引，并在安全条件满足时快进本地 `main` | manifest 注册即运行；首次 bootstrap 默认启用但可用 `HARNESS_AUTO_BOOTSTRAP=0` 或 `bootstrap.auto: false` opt-out；各子行为另有守卫 | 各 Hook 设计为 fail-open、最终不阻断会话；缺组件/环境时提示或 no-op | `session_start_autosync.sh` 可对 `origin/main` 执行有时限的 `git fetch`；首次 bootstrap 可能下载经 sha256 pin 校验的引擎。均不 push/tag |
| `UserPromptSubmit` | 每次用户提交前注入流程状态、L 通道/旁路提示与授权上下文 | 追加项目本地会话 state（用户 prompt/授权台账、提示哨兵） | manifest 注册即运行；双注册时让位避免重复 | 解析、状态目录或辅助脚本失败时 fail-open | 无网络、push 或 tag |
| `PreToolUse` | `Bash` 授权守卫；`Skill` 使用留痕；`Agent|Task` 委派契约门；`Edit|Write|MultiEdit` summary 翻牌门 | 守卫可追加技能/委派/授权消费台账；不代替目标工具写业务文件 | 匹配对应工具时运行；具体 deny 仅在受控规则命中 | 周边解析失败通常 fail-open；明确授权/委派/翻牌规则命中可 exit 2 阻断 | Hook 自身无网络；Bash 门用于阻止未授权 push/merge 等动作 |
| `PostToolUse` | 写工具后检查进度；读/查/Bash 后做批量纪律旁路观测 | 可写项目本地 batch 计数/提示 state；进度检查只读变更摘要 | 匹配对应工具时运行 | 旁路观测与进度检查 fail-open，不改变工具既有结果 | 无网络、push 或 tag |
| `Stop` | 回复结束时检查变更卡进度；可选启动 wiki auto-ingest | 进度检查只读；auto-ingest 可异步写 `wiki/**`、日志与摄取状态，其下游可能形成 wiki 提交 | auto-ingest **默认关闭**，仅 `WIKI_ENGINE_AUTO_INGEST=1` 且 wiki state、组件及凭据守卫齐全时启动 | 守卫缺失静默 no-op；后台启动不阻断 Stop | 启用 auto-ingest 后可能调用外部摄取服务；凭据仅来自环境/组件私有环境文件，禁止入库。未 opt-in 时无出站 |
| `SessionEnd` | 当前未注册 command Hook | 无 | 不适用 | 不适用 | 无 |

矩阵描述的是当前配置与明确脚本行为。运行前仍应审查实际安装版本；本仓开发态与已安装缓存可能不是同一版本。

## 4. 公共分发 manifest：复制集合 SSOT

[`.harness/config/public_distribution_manifest.json`](../../.harness/config/public_distribution_manifest.json) 是公共分发复制集合的结构化 SSOT。它声明复制/生成条目、目录排除、权限保留与公共 README 生成策略。

原有同步脚本与 checker/CI 共同消费这一 manifest：

- `.harness/scripts/sync_public_marketplace.sh` 按 manifest 组装目标目录；
- `.harness/scripts/check_plugin_distribution.py` 校验 manifest 完整性并可比较组装结果；
- `.github/workflows/plugin-distribution.yml` 调用同一本地 checker。

不得在脚本、文档或 CI 中再维护硬编码 plugin/文件白名单，也不得另建第二套同步机制。新增分发资产时先更新结构化 manifest，再由 checker 证明完整性与 parity。

## 5. 隔离组装与 parity

目标目录必须与源仓互不为祖先/后代。同步只做本地组装，不执行 `git`、`gh`、push 或建仓：

```bash
bash .harness/scripts/sync_public_marketplace.sh <target-dir>
python3 .harness/scripts/check_plugin_distribution.py --target <assembled-dir>
```

第二条命令比较 manifest 管理范围内的路径、内容与权限；不要把“同步脚本 exit 0”当作 parity 已成立。发布前还应人工审查目标清单并执行敏感信息扫描。任何疑似 token、API key、私钥、`.env` 或内部资料命中都应阻断公开发布。

## 6. Release-context 标签检查

发布标签验证与普通 PR 分离。只有显式提供本地 Git 仓库和发布 commit/ref 才启用：

```bash
python3 .harness/scripts/check_plugin_distribution.py --tag-repo <local-git-repo> --release-commit <commit-or-ref>
```

该模式只读取显式本地 refs，检查按当前 manifests 动态得到的三个 `{plugin-name}--v{version}` 标签是否共同指向确认的发布 commit。它不 fetch、不创建或更新标签，也不 push。标签创建、覆盖、删除、重打与远端推送均是独立发布动作，必须先向人展示精确 refs 与 commit 并取得单独授权；任一冲突或部分失败应立即停止，不自动补偿。

## 7. 故障定位

| 症状 | 处理 |
|---|---|
| strict validator 不可用 | 安装/修复本地 Claude Code CLI 后重跑；checker 应原样失败，不跳过正式校验 |
| `--report-only` exit 20 | 按 `engine/index/wiki` 与 `command.*` 键定位；非关键命令 degraded 不影响无依赖核心流程 |
| Codegraph 路径缺失或 doctor/status 非零 | 报告真实路径与退出码；由人决定是否运行 `/harness-core:bootstrap`，不自动改 `PATH` |
| `--target` parity 失败 | 检查结构化 manifest、目标多余文件、内容和执行位；重新组装后再验证 |
| release-context 缺标签/指向错误 | 保持只读并停止；核对本地 refs、动态版本和发布 commit，取得精确发布授权后另行处置 |
| 私有 marketplace 401/403 | 核对 Git 读权限与 credential helper；轮换或补授权时不要把凭据写入仓库 |

## 参考

- [Plugin 包结构](../../plugins/README.md)
- [Bootstrap 命令契约](../../plugins/harness-core/commands/bootstrap.md)
- [公共分发 manifest](../../.harness/config/public_distribution_manifest.json)
