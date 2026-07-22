#!/usr/bin/env bash
# Shared read-only merged detection. DME is primary; branch-history matching remains a legacy safety net.
# Callers must run from the repository whose .harness/changes directory contains the card.

merged_detect_sha() {
  card_dir="$1"
  [ -n "$card_dir" ] || return 1
  _md_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$_md_top" ] || return 1
  _md_derive="$_md_top/.harness/scripts/derive_merge_evidence.sh"
  if [ -r "$_md_derive" ]; then
    _md_json="$(bash "$_md_derive" --card "$card_dir" 2>/dev/null || true)"
    _md_sha="$(printf '%s\n' "$_md_json" | python3 -c 'import json,sys
try:
 d=json.load(sys.stdin); s=d.get("merge_commit_sha")
 print(s if d.get("evidence_status")=="AVAILABLE" and isinstance(s,str) else "")
except Exception: print("")' 2>/dev/null || true)"
    if printf '%s' "$_md_sha" | grep -Eq '^[0-9a-f]{40}$'; then
      git merge-base --is-ancestor "$_md_sha" HEAD 2>/dev/null || return 1
      git rev-parse --short "$_md_sha" 2>/dev/null
      return $?
    fi
  fi

  # Legacy safety net for historical unflipped cards with no usable SPI.
  _md_cand="$(git log main --merges --grep "change/$card_dir\$" --format='%H' 2>/dev/null || true)"
  [ -n "$_md_cand" ] || return 1
  for _md_c in $_md_cand; do
    _md_subj="$(git show -s --format=%s "$_md_c" 2>/dev/null || true)"
    printf '%s' "$_md_subj" | grep -Eq "from [^[:space:]]+/change/$card_dir\$" || continue
    git merge-base --is-ancestor "$_md_c" HEAD 2>/dev/null || continue
    git rev-parse --short "$_md_c" 2>/dev/null
    return $?
  done
  return 1
}
