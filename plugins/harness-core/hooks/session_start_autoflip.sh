#!/usr/bin/env bash
# SessionStart legacy safety net: detect merged cards whose PASSED+10 terminal flip is missing.
# Detect-only: never follows SHA placeholders and never writes/commits/pushes/creates cards or PRs.
set -uo pipefail
PREFIX="[harness:autoflip]"
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$TOP" ] || exit 0
cd "$TOP" || exit 0
LIB="$TOP/.harness/scripts/lib/merged_detect.sh"
[ -r "$LIB" ] && . "$LIB" || exit 0
[ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)" = "main" ] || exit 0
[ -z "$(git status --porcelain 2>/dev/null)" ] || exit 0
CHANGES_DIR="$TOP/.harness/changes"
[ -d "$CHANGES_DIR" ] || exit 0
pending_count=0
pending_dirs=""
for summary in "$CHANGES_DIR"/*/summary.md; do
  [ -f "$summary" ] || continue
  card_dir="$(basename "$(dirname "$summary")")"
  [ "$card_dir" = "_TEMPLATE" ] && continue
  status_line="$(grep -E '^\| *总体状态 *\|' "$summary" 2>/dev/null | head -1 || true)"
  stage_line="$(grep -E '^\| *当前阶段 *\|' "$summary" 2>/dev/null | head -1 || true)"
  status_val="$(printf '%s\n' "$status_line" | awk -F'|' '{print $3}' | sed 's/\*\*//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  stage_val="$(printf '%s\n' "$stage_line" | awk -F'|' '{print $3}' | sed 's/\*\*//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ "$status_val" = "PASSED" ] && [ "$stage_val" = "10" ] && continue
  short_sha="$(merged_detect_sha "$card_dir" || true)"
  [ -n "$short_sha" ] || continue
  echo "$PREFIX $card_dir 已合并但终态未翻 (merge $short_sha · ${status_val:-IN_PROGRESS}/阶段${stage_val:-?})" >&2
  pending_count=$((pending_count + 1))
  if [ -z "$pending_dirs" ]; then pending_dirs="$card_dir"; else pending_dirs="$pending_dirs, $card_dir"; fi
done
if [ "$pending_count" -gt 0 ]; then
  echo "$PREFIX ${pending_count} 张历史遗留卡待人工终态处置（${pending_dirs}）；不追 SHA、不自动写回" >&2
fi
exit 0
