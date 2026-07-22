#!/usr/bin/env bash
# Batch read-only DME reconciliation for explicit card basenames.
set -uo pipefail
usage() { printf 'usage: %s --card <basename> [--card <basename> ...]\n' "${0##*/}" >&2; }
fail() { usage; exit 4; }

cards=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --card) [ "$#" -ge 2 ] || fail; cards+=("$2"); shift 2 ;;
    --card=*) cards+=("${1#--card=}"); shift ;;
    *) fail ;;
  esac
done
[ "${#cards[@]}" -gt 0 ] || fail
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$TOP" ] || fail
for card in "${cards[@]}"; do
  printf '%s' "$card" | grep -Eq '^[a-z][a-z0-9]*(-[a-z0-9]+)+-[0-9]{8}$' || fail
  [ -d "$TOP/.harness/changes/$card" ] && [ ! -L "$TOP/.harness/changes/$card" ] || fail
done
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
derive="$script_dir/derive_merge_evidence.sh"
[ -x "$derive" ] || [ -r "$derive" ] || fail
status=0
while IFS= read -r card; do
  if line="$(bash "$derive" --card "$card")"; then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$line"
  case "$rc" in
    3) status=3 ;;
    2) [ "$status" -ne 3 ] && status=2 ;;
    0) ;;
    *) [ "$status" -ne 3 ] && status=2 ;;
  esac
done < <(printf '%s\n' "${cards[@]}" | LC_ALL=C sort -u)
exit "$status"
