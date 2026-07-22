#!/usr/bin/env bash
# Explicit legacy safety-net scan. Merge SHA is derived evidence and is never written back.
# This command is deliberately detect-only: it creates no branch/card/commit/push/PR.
set -uo pipefail
PREFIX="[harness:flip-merged]"
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$TOP" ] || { echo "$PREFIX 非 git 仓库，跳过" >&2; exit 0; }
cd "$TOP" || exit 0
LIB="$TOP/.harness/scripts/lib/merged_detect.sh"
[ -r "$LIB" ] && . "$LIB" || { echo "$PREFIX 缺 merged_detect.sh，跳过" >&2; exit 0; }
CHANGES_DIR="$TOP/.harness/changes"
[ -d "$CHANGES_DIR" ] || exit 0
count=0
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
  echo "$PREFIX $card_dir 已合并但终态未翻（merge $short_sha）；请按 DF-013 人工处置，脚本不回填 SHA、不建分支/卡/PR" >&2
  count=$((count + 1))
done
[ "$count" -gt 0 ] && echo "$PREFIX 共 $count 张历史遗留卡；本次只读，未修改仓库" >&2
exit 0
