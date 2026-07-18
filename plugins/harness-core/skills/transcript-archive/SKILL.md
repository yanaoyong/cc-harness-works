---
name: transcript-archive
trigger: 用户显式调用 `/transcript-archive-enable`，或表达"启用会话 transcript 归档 / 配置归档仓"意图
inputs: 用户提供的 GitHub 私有归档仓 remote URL（必填，无缺省）
outputs: 校验结论（fail-closed）+ `<STATE_HOME>/config.json`（enabled 开关 + 冻结键）+ 后续 opt-in 步骤引导
version: 0.1.0
updated: 2026-07-17
spec: .harness/changes/feat-transcript-archive-20260717/request_analysis/spec.md
---

# Skill · transcript-archive（会话归档启用引导）

> Claude Code 会话 transcript 归档能力的 **opt-in 启用引导**。默认**关闭**——未配置启用时提取器 / hook / 命令**一切不产生副作用**（AC-5）。
> 启用**必须**由用户提供一个 **GitHub 私有归档仓** remote URL，经 fail-closed 校验（仓可达 + 确为 private + 首次 clone/复用）后方写配置。归档含会话原始记录，**禁止入公有 / internal 仓**。

## 1. 前置条件（缺任一 = 无法启用）

1. **`gh` CLI 可用且已登录**（`gh auth login`）——启用校验用 `gh api` 查归档仓 visibility。**`gh` 缺失 = visibility 查不到 = fail-closed 拒绝启用**（这是设计，不是 bug）。
2. **Python 3.11+**（`python3`）——提取器与本启用脚本的 config 读写均依赖 stdlib，无第三方依赖。
3. **一个 GitHub 私有仓**作归档仓（专仓，非业务仓 / 非公有分发仓）。建议命名如 `<you>/claude-transcript-archive`（**私有**）。
4. `git` 可用。

## 2. 启用步骤

### 2.1 提供私有归档仓 URL 并运行校验脚本

把你的私有归档仓 remote URL 交给我，我会运行启用校验脚本（**不默推 remote、不硬编码任何用户级取值**）：

```bash
# 校验脚本 (随 skill 分发):
#   plugins/harness-core/skills/transcript-archive/scripts/enable_archive.sh   (本仓开发态)
# 消费方安装态经 CLAUDE_PLUGIN_ROOT 定位:
#   "$CLAUDE_PLUGIN_ROOT/skills/transcript-archive/scripts/enable_archive.sh"
#
# 用法 (remote 必填, 支持 https:// 与 git@ 两形态):
bash <定位到的>/enable_archive.sh https://github.com/<you>/claude-transcript-archive.git
# 或
bash <定位到的>/enable_archive.sh git@github.com:<you>/claude-transcript-archive.git
```

### 2.2 校验链（fail-closed · 任一失败即拒绝启用、不写 config）

| 阶段 | 通过条件 | 失败 → 退出码 |
|---|---|---|
| gh 存在 | `gh` 在 PATH | 缺失 → exit 3（fail-closed） |
| owner/repo 解析 | remote 形如 `.../<o>/<r>(.git)` | 无法解析 → exit 4 |
| visibility 私有 | `gh api repos/<o>/<r> --jq .visibility` == `private` | 查不到 → exit 5；非 private → exit 6 |
| 归档仓落地 | archive_dir 是已有 git 仓（跳过 clone）/ 不存在 / 空目录（clone） | 非空非 git → exit 7；clone 失败 → exit 8 |

校验全过 → 写 `<STATE_HOME>/config.json`（`enabled:true` + remote + 各冻结键缺省；**已有 config 则合并保留用户自定键值**）。我会把每步结论呈现给你；任一失败会给出明确原因与修复建议。

### 2.3 STATE_HOME 与配置文件位置

- **STATE_HOME** = 环境变量 `HARNESS_TRANSCRIPT_ARCHIVE_HOME`，缺省 `~/.claude/harness-transcript-archive`。
- **配置文件** = `<STATE_HOME>/config.json`。
- 水位文件 `watermarks.json` 也落 STATE_HOME（机器本地状态、不入归档仓 · 多机场景防 push 冲突）。

## 3. 配置键说明（config.json · 冻结契约）

| 键 | 类型 | 缺省 | 说明 |
|---|---|---|---|
| `enabled` | bool | `false`（未启用即无此文件） | 总开关。false / 无 config = 一切零副作用 |
| `archive_remote` | str | 无（必填，来自启用参数） | GitHub 私有归档仓 remote URL |
| `archive_dir` | str | `<STATE_HOME>/archive` | 热层（lean 明文）本地 clone 落点 |
| `cold_dir` | str | `<STATE_HOME>/cold` | 冷层（raw `.jsonl.gz` + 附属 `tar.gz`）本机目录；**不入 GitHub** |
| `cold_retention_days` | int | `0`（=永不回收） | 冷层保留天数；0 表示不自动回收 |
| `denylist_path` | str | `""`（可空） | 消费方可扩脱敏 denylist 文件路径；逐条 `re.compile`，编译失败条目 skip+warning 不中止 |
| `cold_sync_cmd` | str | `""`（空=仅本机） | 冷层落盘成功后执行的**非本机同步命令**（rclone/scp/对象存储 CLI）；空则冷层仅留本机 |
| `lock_stale_seconds` | int | `600` | flock 锁龄阈值（秒）；持锁者超此时长视为卡死 → 告警上抛 |
| `source_exclude` | list[str] | `[]` | 追加 fnmatch 排除模式，与内置默认 `*tmp*` / `*fixture*` / `*acceptance*` 共同生效；追加不覆盖默认清单 |

> 手动改 config.json 后无需重启；下一次 `sync` 即读新值。改键值时保持类型正确（bool/int/str）。

## 3.1 全机单例归档心智模型

归档仓是**全机单例**，不是按项目隔离的：

1. **`STATE_HOME` / `SOURCE_ROOT` 全机唯一**：`STATE_HOME` 缺省为 `~/.claude/harness-transcript-archive`，`SOURCE_ROOT` 缺省为 `~/.claude/projects`。消费方通过 `CLAUDE_PLUGIN_ROOT` 定位到同一套脚本，同一台机器上所有 Claude Code 项目共用同一归档仓。
2. **任何项目触发 sync 都归档全机会话**：在任意项目里跑 `sync` / `backfill`，脚本都会扫描全机 `SOURCE_ROOT` 下的全部项目会话并写入同一归档仓。不存在“按项目归档到不同仓”的设计。
3. **禁止按项目设置 `HARNESS_TRANSCRIPT_ARCHIVE_HOME`**：若在不同项目/目录分别设置该环境变量，同一批会话会被复制到多个归档仓，造成**真·重复归档**，后续去重、清理与索引都会错乱。
4. **硬门伪命中核实 → 放行 SOP**：`_hard_gate_before_commit` 可能把一次性整理脚本误判为风险。核实为误报后，把其 `fingerprint` 追加写入 `config.json` 的 `hard_gate_allow_fingerprints` 列表即可放行；该列表是追加而非覆盖。

## 4. 启用后的 opt-in 后续步骤（均手动、按需开启）

### 4.1 存量止血备份（一次性 · 不自动化 · spec OUT）

启用只归档**新增**会话；存量约 1 GB 会话仍受 Claude Code 默认清理威胁。**建议先做一次性快照备份**到持久卷（本插件**不自动化**此步）：

```bash
# 一次性 gz 快照 ~/.claude/projects 到持久卷 (示例, 按需改目标路径):
tar czf "$HOME/claude-projects-snapshot-$(date +%Y%m%d).tar.gz" -C "$HOME/.claude" projects
# 或 rsync 到外部卷 / 网盘挂载点:
#   rsync -a "$HOME/.claude/projects/" /mnt/persistent/claude-projects-backup/
```

启用后可再跑 `transcript_archive.py backfill` 做首次全量提取入归档仓（CLI 由 T3 交付）。

### 4.2 建议放宽 `cleanupPeriodDays`（仅提示 · 不替改 · spec OUT）

Claude Code 默认 `cleanupPeriodDays` 约 30 天静默清理会话文件。**建议**在你的 Claude Code settings 中调大（如 `365`），给归档流足够窗口：

```jsonc
// ~/.claude/settings.json (你自行编辑, 本插件不替你改):
{ "cleanupPeriodDays": 365 }
```

> 仅建议值，最终由你决定；本插件**不替你修改** `cleanupPeriodDays`。

### 4.3 SessionEnd hook 注册（opt-in · 会话结束自动 sync）

hook 本体 `hooks/session_end_transcript.sh` 由 T5 交付（未启用零动作）。手动注册到 `.claude/settings.local.json`（**opt-in**）：

```jsonc
// .claude/settings.local.json — hooks.SessionEnd 追加一项:
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session_end_transcript.sh\"" }
        ]
      }
    ]
  }
}
```

> worktree 免疫说明：关联提取纯离线读 JSONL，不依赖运行时 hook 存活。SessionEnd hook 只是三入口之一（手动 / cron / hook 同一脚本），worktree 下 hook 即便被杀，cron / 手动入口仍可归档。

### 4.4 cron 定时归档（opt-in）

cron 样例由 T5 交付于 `scripts/transcript_archive_cron.sample`。参考该样例注册 crontab（按需，示例仅指引方向）：

```bash
# 查看样例后按需 crontab -e 注册, 例如每小时:
#   0 * * * * python3 <定位到的>/transcript_archive.py sync >> <STATE_HOME>/cron.log 2>&1
cat <定位到的>/scripts/transcript_archive_cron.sample
```

### 4.5 denylist / cold_sync_cmd / 保留策略（按需配置 config 键）

- **denylist**（`denylist_path`）：在归档仓/本地放一个每行一条正则的文件，追加脱敏规则；命中替换为 `【REDACTED:<类型>】`。编译失败条目自动 skip+warning、内置 secret 族仍生效（fail-safe，不 fail-open）。
- **cold_sync_cmd**（非本机冷层去向）：每个新落盘的冷层产物执行一次。命令按 argv 数组
  （`shell=False`、命令与数据分离防注入）展开，目标冷层路径以下述**两形态之一**注入：
  - **占位符替换式**（推荐 · 支持「源在前、目的在后」）：命令中写 `{COLD_PATH}` 占位符，
    脚本把**每个**参数里的 `{COLD_PATH}` 替换为真实冷层路径、**不再追加**：
    ```bash
    # rclone 到对象存储 / 网盘（源在前、目的在后）:
    #   "cold_sync_cmd": "rclone copy {COLD_PATH} myremote:claude-cold"
    # scp 到远端主机:
    #   "cold_sync_cmd": "scp {COLD_PATH} user@host:/backup/claude-cold/"
    ```
  - **尾追式**（向后兼容）：命令**不含** `{COLD_PATH}` 时，冷层路径自动**追加为末位参数**。
    仅适合「工具 + 固定前缀参数 + 末位取源」形态；若工具要求源在前、目的在后，请用占位符式。
  - 需管道 / 重定向 / 变量展开等 shell 特性时，自行以 `sh -c '<...>'` 作为命令包裹
    （占位符仍可用，如 `"cold_sync_cmd": "sh -c 'gzip -c {COLD_PATH} | ...'"`）。

  **不受控介质加密由你自行在命令中套 `age` / `gpg`**（例：`cold_sync_cmd` 内先 `age -r <key>` 再上传）——**插件本体保持纯 stdlib、不调用任何加密二进制、不产出加密态**。
- **cold_retention_days**：冷层保留窗口（0=永不回收）；`lock_stale_seconds`：并发锁龄阈值（缺省 600s）。

### 4.6 `migrate-layout` 子命令（一次性 layout 整理）

如果你之前使用早期版本归档，仓根下可能存在形如 `<project>--claude-worktrees-<wt>` 的 worktree 顶级目录。运行一次 `migrate-layout` 可把这类目录整理为 `<project>/_worktrees/<wt>/`：

```bash
python3 <定位到的>/transcript_archive.py migrate-layout
```

- **仅操作归档仓**：不碰 `source_root`、水位文件与冷层。
- **仅本地 commit**：不会 `push` 到远端；整理结果留在本地归档仓，供你审阅后再决定是否推送。
- **执行前要求工作树干净**：若硬门命中，请先核实误报并把 `fingerprint` 追加到 `hard_gate_allow_fingerprints`。
- **建议先备份**：脚本内部使用 `git mv` 保留历史，但整理前仍建议先对归档仓做一次快照或 push 当前状态。

执行后会重建 `index.tsv` 与 `by-instance/`；二次运行幂等。

## 5. 未启用 = 零副作用（AC-5 保证）

无 `config.json` 或 `enabled:false` 时：提取器 / SessionEnd hook / cron 入口**全部零动作**——无落盘、无 commit、无外呼。启用是显式动作，本 skill + `enable_archive.sh` 是唯一入口。

## 6. 故障排除

- **exit 3（gh 缺失）**：装 GitHub CLI 并 `gh auth login`。这是 fail-closed 设计——无 gh 就查不到 visibility，宁拒不放。
- **exit 5（visibility 查不到）**：确认仓存在、`gh` 已登录且对该仓有权限、网络可达。
- **exit 6（非 private）**：把归档仓改为 **private**，或换一个私有仓。归档含会话原文，禁入公有 / internal。
- **exit 7（archive_dir 非空非 git）**：清空 `<STATE_HOME>/archive`，或在 config 里指定其它空的 `archive_dir` 后重跑。
- **exit 8（clone 失败）**：检查网络 / 凭证 / remote 正确性；启用未生效（未写 config），修复后重跑即可。
