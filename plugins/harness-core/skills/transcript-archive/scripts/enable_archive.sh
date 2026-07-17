#!/usr/bin/env bash
set -euo pipefail
#
# enable_archive.sh — transcript-archive 启用校验 (fail-closed)
# 变更卡 feat-transcript-archive-20260717 · T4 · 满足 AC-5
#
# 用法:
#   enable_archive.sh <github-private-remote-url>
#
# 校验链 (任一失败 = 非零退出 + 明确原因 · 不写 config · 启用不生效):
#   1. gh CLI 缺失            → 拒绝 (gh 缺失=visibility 查不到=fail-closed·AC-5)
#   2. 无法解析 owner/repo    → 拒绝
#   3. gh api 查 visibility：查不到 / 非 private → 拒绝
#   4. 校验通过 → clone 到 archive_dir
#        · 已存在且是 git 仓 → 跳过 clone (复用)
#        · 目录不存在 / 空目录 → git clone
#        · 非 git 且非空       → 拒绝 (防覆盖)
#   5. 写 <STATE_HOME>/config.json (enabled:true + 冻结键缺省; 已有 config 合并保留用户自定键值)
#
# 硬约束:
#   · 不默推 remote (必须由参数传入); 不硬编码任何用户级取值 (remote/路径全来自参数或环境变量)
#   · 禁真实密钥/token (CODE-005/GEN-3): 本脚本不读写任何 API key, gh 凭证由 gh 自身管理
#   · 外呼命令 argv 化, 禁 eval 拼接
#
# 环境变量:
#   HARNESS_TRANSCRIPT_ARCHIVE_HOME  覆盖 STATE_HOME (缺省 ~/.claude/harness-transcript-archive)
#
# 退出码:
#   0 成功启用 | 2 用法错误 | 3 gh 缺失 | 4 无法解析 owner/repo
#   5 visibility 查不到 | 6 visibility 非 private | 7 archive_dir 非空非 git | 8 clone 失败

err()  { printf '[transcript-archive:enable] ERROR: %s\n' "$*" >&2; }
info() { printf '[transcript-archive:enable] %s\n'        "$*" >&2; }

REMOTE="${1:-}"
if [ -z "$REMOTE" ]; then
  err "缺少归档仓 remote URL 参数。用法: enable_archive.sh <github-private-remote-url>"
  exit 2
fi

STATE_HOME="${HARNESS_TRANSCRIPT_ARCHIVE_HOME:-$HOME/.claude/harness-transcript-archive}"
CONFIG="$STATE_HOME/config.json"
ARCHIVE_DIR_DEFAULT="$STATE_HOME/archive"
COLD_DIR_DEFAULT="$STATE_HOME/cold"

# --- 1. gh CLI 缺失 → fail-closed 拒绝 -------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  err "gh CLI 缺失 → 无法查询归档仓 visibility → fail-closed 拒绝启用 (AC-5)。请先安装 GitHub CLI 并 gh auth login 后重试。"
  exit 3
fi

# --- 2. 解析 owner/repo (支持 https / git@ / ss:// 三形态) ------------------
_r="${REMOTE%.git}"
owner="" ; repo=""
if [[ "$_r" =~ [:/]([^/:]+)/([^/:]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
fi
if [ -z "$owner" ] || [ -z "$repo" ]; then
  err "无法从 remote 解析 owner/repo: $REMOTE (支持 https://github.com/<o>/<r> 或 git@github.com:<o>/<r>)。"
  exit 4
fi

# --- 3. 查询 visibility (fail-closed: 查不到 / 非 private 均拒绝) -----------
visibility="$(gh api "repos/${owner}/${repo}" --jq '.visibility' 2>/dev/null || true)"
if [ -z "$visibility" ]; then
  err "gh api 查不到 repos/${owner}/${repo} 的 visibility (仓库不存在 / 无权限 / 网络失败) → fail-closed 拒绝启用。"
  exit 5
fi
if [ "$visibility" != "private" ]; then
  err "归档仓 visibility=${visibility} 非 private → 拒绝启用 (私有仓 fail-closed · AC-5)。归档含会话原始记录, 禁止入公有 / internal 仓。"
  exit 6
fi
info "visibility 校验通过: repos/${owner}/${repo} = private"

# --- 4. clone / 复用归档仓 -------------------------------------------------
# 已有 config 中的 archive_dir 优先 (合并语义: 尊重用户此前自定路径)
ARCHIVE_DIR="$ARCHIVE_DIR_DEFAULT"
if [ -f "$CONFIG" ]; then
  _existing_dir="$(python3 - "$CONFIG" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        c = json.load(f)
    v = c.get("archive_dir")
    print(v if isinstance(v, str) and v else "")
except Exception:
    print("")
PY
)"
  [ -n "$_existing_dir" ] && ARCHIVE_DIR="$_existing_dir"
fi

if [ -e "$ARCHIVE_DIR/.git" ]; then
  info "归档仓已存在于 $ARCHIVE_DIR (git 仓) → 跳过 clone (复用)。"
elif [ -d "$ARCHIVE_DIR" ] && [ -n "$(ls -A "$ARCHIVE_DIR" 2>/dev/null)" ]; then
  err "$ARCHIVE_DIR 非空且非 git 仓 → 拒绝 clone (防覆盖用户数据)。请清空该目录或指定其它 archive_dir 后重试。"
  exit 7
else
  info "clone $REMOTE → $ARCHIVE_DIR ..."
  mkdir -p "$(dirname "$ARCHIVE_DIR")"
  if ! git clone "$REMOTE" "$ARCHIVE_DIR"; then
    err "git clone 失败 → fail-closed 未写 config (启用未生效)。检查网络 / 凭证 / remote 后重试。"
    exit 8
  fi
fi

# --- 5. 写 config.json (合并保留已有键 · 冻结键缺省) -----------------------
mkdir -p "$STATE_HOME"
python3 - "$CONFIG" "$REMOTE" "$ARCHIVE_DIR" "$COLD_DIR_DEFAULT" <<'PY'
import json, os, sys
config_path, remote, archive_dir, cold_dir = sys.argv[1:5]
cfg = {}
if os.path.exists(config_path):
    try:
        with open(config_path) as f:
            cfg = json.load(f)
        if not isinstance(cfg, dict):
            cfg = {}
    except Exception:
        cfg = {}
# 冻结键 + 缺省值 (T4 契约); setdefault = 已有用户自定键值保留不覆盖
defaults = {
    "enabled": True,
    "archive_remote": remote,
    "archive_dir": archive_dir,
    "cold_dir": cold_dir,
    "cold_retention_days": 0,      # 0 = 永不回收
    "denylist_path": "",           # 可空
    "cold_sync_cmd": "",           # 空 = 仅本机
    "lock_stale_seconds": 600,
}
for k, v in defaults.items():
    cfg.setdefault(k, v)
# 本次启用的显式意图: 强制这三项为本次校验通过的值
cfg["enabled"] = True
cfg["archive_remote"] = remote
cfg["archive_dir"] = archive_dir
with open(config_path, "w") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
PY

info "启用完成: 已写 $CONFIG (enabled=true)。"
info "后续 opt-in 步骤 (SessionEnd hook / cron 注册 / denylist / cold_sync_cmd) 见 skill 引导。"
