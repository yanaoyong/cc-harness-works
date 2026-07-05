#!/usr/bin/env bash
# setup_statusline.sh — Harness Core Plugin SessionStart Hook（statusline 半自动写入）
# 职责：消费方项目安装 harness-core plugin 后，若项目尚未配置 statusLine，
#       半自动向 $TOP/.claude/settings.json JSON-safe 合并写入 statusLine 配置，
#       指向脚手架落盘的项目副本 .harness/scripts/statusline.sh（绝不指 plugin 缓存路径）。
#
# 守卫序列（任一不满足 → 静默/留痕 exit 0，全部 fail-open）：
#   ① TOP 定位：git rev-parse --show-toplevel 失败 → 静默 exit 0
#   ② 哨兵：$TOP/.harness/state/.statusline_configured 存在 → exit 0
#      （主位置恒 $TOP/.harness/state/；CLAUDE_PLUGIN_DATA 仅作后备读旧哨兵兼容）
#   ③ 已有配置检测：settings.json 或 settings.local.json 任一含 "statusLine" 键字样
#      → 不写入，补落哨兵（幂等自愈 · 补哨兵前 stderr 留痕一行）后 exit 0
#   ④ 落盘副本：$TOP/.harness/scripts/statusline.sh 不存在/不可读
#      → exit 0（不落哨兵，下会话 scaffold 落盘后重试）
#
# 写入纪律（R1：写用户项目配置属侵入动作，必须留痕）：
#   - python3 json 模块优先：合并写入、保留既有键；非法 JSON → 留痕 + 不写 + 不落哨兵
#   - 无 python3：settings.json 不存在 → heredoc 写全新最小文件；
#                 已存在 → 放弃写入留痕 exit 0（不冒险文本拼接破坏 JSON）
#   - 写入成功 → 落哨兵 + stderr 留痕（statusLine 写入通常下会话生效，首会话不显示属预期）
#
# 设计原则：恒 exit 0（任何分支，不阻断 session）；不修改 git config，无全局副作用。
# bash 3.2 兼容：不使用 declare -A / mapfile / readarray / realpath
set -uo pipefail

PREFIX="[harness:setup-statusline]"

log_info()  { echo "$PREFIX $*" >&2; }
log_warn()  { echo "$PREFIX ⚠️  $*" >&2; }

# ============================================================
# 守卫①：定位仓库根
# ============================================================

TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$TOP" ]; then
  exit 0
fi

STATE_DIR="$TOP/.harness/state"
SENTINEL="$STATE_DIR/.statusline_configured"

SETTINGS="$TOP/.claude/settings.json"
SETTINGS_LOCAL="$TOP/.claude/settings.local.json"

# statusLine 指向项目落盘副本（绝不指 plugin 缓存路径）
SL_COMMAND='bash "${CLAUDE_PROJECT_DIR:-.}/.harness/scripts/statusline.sh"'

# ------------------------------------------------------------
# 哨兵落盘（主位置恒 $TOP/.harness/state/）
# ------------------------------------------------------------

_drop_sentinel() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  date '+%Y-%m-%d %H:%M:%S' > "$SENTINEL" 2>/dev/null || return 1
  return 0
}

# ============================================================
# 守卫②：哨兵检查（一次性写入，防每会话重写）
# ============================================================

if [ -f "$SENTINEL" ]; then
  exit 0
fi
# CLAUDE_PLUGIN_DATA 仅作后备读旧哨兵（兼容历史位置），不作主写入位置
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -f "${CLAUDE_PLUGIN_DATA}/.statusline_configured" ]; then
  exit 0
fi

# ============================================================
# 守卫③：已有配置检测（两文件任一含 "statusLine" 键字样 → 不覆盖）
# ============================================================

_has_statusline=0
for _f in "$SETTINGS" "$SETTINGS_LOCAL"; do
  if [ -f "$_f" ] && grep -q '"statusLine"' "$_f" 2>/dev/null; then
    _has_statusline=1
    break
  fi
done

if [ "$_has_statusline" -eq 1 ]; then
  log_info "检测到项目已有 statusLine 配置，不写入；补落哨兵（幂等自愈）"
  _drop_sentinel || true
  exit 0
fi

# ============================================================
# 守卫④：落盘副本存在性（scaffold 未落盘则下会话重试，不落哨兵）
# ============================================================

if [ ! -r "$TOP/.harness/scripts/statusline.sh" ]; then
  log_info "落盘副本 .harness/scripts/statusline.sh 缺失或不可读，本会话跳过（scaffold 落盘后自动重试）"
  exit 0
fi

# ============================================================
# JSON-safe 写入 settings.json
# ============================================================

mkdir -p "$TOP/.claude" 2>/dev/null || exit 0

_wrote=0

if command -v python3 >/dev/null 2>&1; then
  # python3 合并写入：保留既有键；非法 JSON → exit 2 → 留痕不写不落哨兵
  SL_COMMAND="$SL_COMMAND" python3 - "$SETTINGS" <<'PYEOF'
import json, os, sys

path = sys.argv[1]
data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        sys.exit(2)
    if not isinstance(data, dict):
        sys.exit(2)

data["statusLine"] = {
    "type": "command",
    "command": os.environ["SL_COMMAND"],
    "padding": 0,
}

tmp = path + ".harness-setup-statusline.tmp"
try:
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
except Exception:
    try:
        os.path.exists(tmp) and os.remove(tmp)
    except Exception:
        pass
    sys.exit(3)
sys.exit(0)
PYEOF
  _py_rc=$?
  if [ "$_py_rc" -eq 0 ]; then
    _wrote=1
  elif [ "$_py_rc" -eq 2 ]; then
    log_warn "settings.json 非法 JSON（或非对象），拒绝触碰；请人工检查 $SETTINGS"
    exit 0
  else
    log_warn "settings.json 写入失败（python3 rc=$_py_rc），本会话跳过"
    exit 0
  fi
else
  # 无 python3：仅在 settings.json 不存在时写全新最小文件；已存在则不冒险文本拼接
  if [ -f "$SETTINGS" ]; then
    log_info "无 python3 且 settings.json 已存在，放弃合并写入（不冒险破坏 JSON）；可人工配置 statusLine"
    exit 0
  fi
  cat > "$SETTINGS" <<'JSONEOF'
{
  "statusLine": {
    "type": "command",
    "command": "bash \"${CLAUDE_PROJECT_DIR:-.}/.harness/scripts/statusline.sh\"",
    "padding": 0
  }
}
JSONEOF
  if [ $? -eq 0 ]; then
    _wrote=1
  else
    log_warn "settings.json 创建失败，本会话跳过"
    exit 0
  fi
fi

# ============================================================
# 收尾：落哨兵 + 留痕
# ============================================================

if [ "$_wrote" -eq 1 ]; then
  _drop_sentinel || log_warn "哨兵落盘失败（$SENTINEL），下会话检测逻辑将幂等自愈"
  log_info "statusLine 已写入 .claude/settings.json（指向 .harness/scripts/statusline.sh），通常下会话生效"
fi

exit 0
