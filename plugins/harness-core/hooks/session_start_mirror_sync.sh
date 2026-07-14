#!/usr/bin/env bash
# SessionStart 钩子：版本戳触发的镜像分层刷新宿主（fix-mirror-upgrade-propagation-20260714 · T8 · FR-10）。
#
# 时序（hooks.json SessionStart 数组）：session-start.sh（①脚手架）→ **本 hook（②同步刷新）**
#   → session_start_resident_contract.sh（③契约注入）→ autosync/…。
#   注册于 ①② 之间使刷新**同会话早于契约注入**生效——契约注入链①优先吃 .harness/ 镜像，
#   本 hook 先把镜像刷成权威源较新态 → 注入即得新契约（E-2 达成判据）。
#   不受 .bootstrap_done 门控、不依赖 harness_bootstrap.sh 触发路径。
#
# 运行语义：
#   - 读已装 plugin version（base 内 plugin.json），与镜像侧版本戳比对；
#     一致 → **秒退零动作**（日常零开销 · R-6：重操作严格置于"不一致"分支之后）；
#     不一致 → 全量分层刷新（仅升级后首会话一次）→ commit-last 写版本戳。
#   - commit-last（FR-11）：仅在全部机器件/半定制件刷新**无非预期失败**且**无 components 让路**时写版本戳；
#     否则版本戳不推进 + stderr 降级报告，下会话重试。FR-6 本地改动保护性跳过=预期态、不阻 commit-last。
#
# hook 纪律（FR-8 · AC-9）：任何路径恒 exit 0；失败/缺项降级带 stderr 警告（前缀 [mirror-sync]）；
#   bash 3.2 兼容（无 declare -A / mapfile / readarray）。
set -uo pipefail

PREFIX="[mirror-sync]"

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
LIB_DIR="$SELF_DIR/../scripts/lib"

# harness_state_root 供给（shell-utils 若可读则 source · 否则 mirror_sync_lib 内联兜底同口径）
[ -r "$LIB_DIR/shell-utils.sh" ] && . "$LIB_DIR/shell-utils.sh" 2>/dev/null || true

if [ ! -r "$LIB_DIR/mirror_sync_lib.sh" ]; then
  echo "$PREFIX mirror_sync_lib.sh 缺失（$LIB_DIR），跳过刷新（降级 · 不阻断会话）" >&2
  exit 0
fi
# shellcheck disable=SC1090
. "$LIB_DIR/mirror_sync_lib.sh" 2>/dev/null || {
  echo "$PREFIX mirror_sync_lib.sh 不可 source，跳过刷新（降级）" >&2
  exit 0
}

# 守卫：仓库根定位（内容 base 定位用 · 与 _persist_component 家法对齐）
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TOP" ] && exit 0
cd "$TOP" || exit 0

# 权威源 base（NS-1 · version 与 content 同 base）
BASE="$(mirror_sync_resolve_base "$TOP")"
if [ -z "$BASE" ]; then
  echo "$PREFIX 权威源 base 不可解析（无 plugins/harness-core/.claude-plugin/plugin.json 且 CLAUDE_PLUGIN_ROOT 不可用），跳过" >&2
  exit 0
fi

SDIR="$(mirror_sync_state_dir)"
MANIFEST="$BASE/sync-manifest"
if [ ! -r "$MANIFEST" ]; then
  echo "$PREFIX sync-manifest 缺失（$MANIFEST），跳过刷新（降级）" >&2
  exit 0
fi

CUR_VER="$(mirror_sync_read_version "$BASE" || true)"
if [ -z "$CUR_VER" ]; then
  echo "$PREFIX 无法读取 plugin version（$BASE/.claude-plugin/plugin.json），跳过刷新（降级）" >&2
  exit 0
fi
STAMP_VER="$(mirror_sync_read_stamp "$SDIR" || true)"

# ── R-6：版本戳一致秒退（重操作严格在此分支之后）──
if [ "$CUR_VER" = "$STAMP_VER" ]; then
  exit 0
fi

# 自锁（fail-open · 另一 mirror-sync 在跑则让路、下会话重试）
if ! mirror_sync_lock_acquire "$SDIR"; then
  echo "$PREFIX 另一 mirror-sync 正在运行，跳过本次刷新（下会话重试）" >&2
  exit 0
fi
trap 'mirror_sync_lock_release "$SDIR"' EXIT

echo "$PREFIX 版本戳不一致（stamp=${STAMP_VER:-<none>} → plugin=$CUR_VER），开始镜像分层刷新..." >&2

mirror_sync_run "$TOP" "$BASE" "$SDIR" "$MANIFEST" || true

# ── commit-last 判定（FR-11）──
if [ "${MIRROR_SYNC_FAILED:-1}" = "0" ] && [ "${MIRROR_SYNC_DEFERRED:-0}" = "0" ]; then
  if mirror_sync_write_stamp "$SDIR" "$CUR_VER"; then
    echo "$PREFIX 镜像刷新完成，版本戳推进 → $CUR_VER（镜像 diff 待人工提交 · 不 auto-commit · DF-007）" >&2
  else
    echo "$PREFIX 版本戳写入失败，下会话重试" >&2
  fi
elif [ "${MIRROR_SYNC_DEFERRED:-0}" = "1" ]; then
  echo "$PREFIX components 类因后台 bootstrap 并发让路，版本戳不推进（下会话补齐 · NS-2）" >&2
else
  echo "$PREFIX 刷新存在非预期失败，版本戳不推进（下会话重试）· 详见上方冲突报告" >&2
fi

exit 0
