#!/usr/bin/env bash
# Derive read-only merge evidence for one explicit change card.
set -uo pipefail

SCHEMA_VERSION="1"
usage() { printf 'usage: %s --card <basename>\n' "${0##*/}" >&2; }
die_usage() { usage; exit 4; }

card=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --card) [ "$#" -ge 2 ] || die_usage; card="$2"; shift 2 ;;
    --card=*) card="${1#--card=}"; shift ;;
    *) die_usage ;;
  esac
done
[ -n "$card" ] || die_usage
printf '%s' "$card" | grep -Eq '^[a-z][a-z0-9]*(-[a-z0-9]+)+-[0-9]{8}$' || die_usage

TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$TOP" ] || die_usage
card_path="$TOP/.harness/changes/$card"
summary="$card_path/summary.md"
[ -d "$card_path" ] && [ ! -L "$card_path" ] && [ -f "$summary" ] || die_usage

json_out() {
  python3 - "$SCHEMA_VERSION" "$card" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" <<'PY'
import json, sys
keys = ("schema_version", "card", "repository", "pr_number", "pr_url", "pr_state",
        "evidence_status", "merged_at", "merge_commit_sha", "source")
vals = list(sys.argv[1:])
for index in (2, 3, 4, 7, 8):
    if vals[index] == "":
        vals[index] = None
if vals[3] is not None:
    vals[3] = int(vals[3])
print(json.dumps(dict(zip(keys, vals)), separators=(",", ":"), ensure_ascii=False))
PY
}

# origin wins. Without origin, exactly one canonical GitHub repository identity is accepted.
remote_ids="$(git -C "$TOP" remote -v 2>/dev/null | python3 -c '
import re, sys
origin, all_ids = [], []
pattern = re.compile(r"^(?:https://github\.com/|ssh://git@github\.com/|git@github\.com:)([^/\s]+)/([^/\s]+?)(?:\.git)?$")
for line in sys.stdin:
    parts = line.rstrip("\n").split()
    if len(parts) < 2:
        continue
    match = pattern.match(parts[1])
    if not match:
        continue
    identity = match.group(1) + "/" + match.group(2)
    all_ids.append(identity)
    if parts[0] == "origin":
        origin.append(identity)
chosen = sorted(set(origin)) if origin else sorted(set(all_ids))
print("\n".join(chosen))
')"
repo_count="$(printf '%s\n' "$remote_ids" | grep -c . || true)"
if [ "$repo_count" -ne 1 ]; then
  json_out "" "" "" "UNKNOWN" "UNAVAILABLE" "" "" "none"
  exit 2
fi
repository="$remote_ids"

# Parse only the stage-7 output cell. Selection priority is full SPI, URL-only, then PR-number-only.
spi="$(python3 - "$summary" "$repository" <<'PY'
import re, sys
path, repository = sys.argv[1:]
rows = []
with open(path, encoding="utf-8") as stream:
    for line in stream:
        cells = [cell.strip() for cell in line.rstrip("\n").split("|")[1:-1]]
        if cells and re.fullmatch(r"7\s+代码推送", cells[0]):
            rows.append(cells[-1])
if len(rows) != 1:
    print("AMBIGUOUS" if len(rows) > 1 else "UNAVAILABLE")
    raise SystemExit
cell = rows[0]
url_pattern = re.compile(r"https://github\.com/([^/\s|]+/[^/\s|]+)/pull/([0-9]+)(?![/A-Za-z0-9?#])")
urls = url_pattern.findall(cell)
url_tokens = re.findall(r"https://github\.com/", cell)
number_tokens = re.findall(r"\bPR\s*#([0-9]+)\b", cell)
if len(urls) > 1 or len(number_tokens) > 1 or len(url_tokens) != len(urls):
    print("AMBIGUOUS")
    raise SystemExit
if urls:
    repo, number = urls[0]
    canonical = f"https://github.com/{repo}/pull/{number}"
    if repo != repository or len(url_tokens) != 1:
        print("AMBIGUOUS")
        raise SystemExit
    if number_tokens and number_tokens[0] != number:
        print("AMBIGUOUS")
        raise SystemExit
    print(f"OK\t{number}\t{canonical}")
    raise SystemExit
if len(number_tokens) == 1:
    number = number_tokens[0]
    print(f"OK\t{number}\thttps://github.com/{repository}/pull/{number}")
    raise SystemExit
print("UNAVAILABLE")
PY
)"
spi_status="${spi%%$'\t'*}"
if [ "$spi_status" = "AMBIGUOUS" ]; then
  json_out "$repository" "" "" "UNKNOWN" "AMBIGUOUS" "" "" "none"
  exit 3
fi
if [ "$spi_status" != "OK" ]; then
  json_out "$repository" "" "" "UNKNOWN" "UNAVAILABLE" "" "" "none"
  exit 2
fi
rest="${spi#*$'\t'}"
pr_number="${rest%%$'\t'*}"
pr_url="${rest#*$'\t'}"

fallback=0
if ! command -v gh >/dev/null 2>&1; then
  fallback=1
else
  gh_err="$(mktemp)"
  trap 'rm -f "$gh_err"' EXIT
  gh_data="$(timeout 15 gh pr view "$pr_number" --repo "$repository" \
    --json number,url,state,mergedAt,mergeCommit \
    --jq '[.number,.url,.state,(.mergedAt // ""),(.mergeCommit.oid // "")] | @tsv' 2>"$gh_err")"
  gh_rc=$?
  if [ "$gh_rc" -eq 0 ]; then
    IFS=$'\t' read -r got_number got_url state merged_at merge_sha <<EOF
$gh_data
EOF
    if [ "$got_number" != "$pr_number" ] || [ "$got_url" != "$pr_url" ]; then
      json_out "$repository" "$pr_number" "$pr_url" "UNKNOWN" "AMBIGUOUS" "" "" "none"
      exit 3
    fi
    if [ -n "$merged_at" ] || [ "$state" = "MERGED" ]; then
      if printf '%s' "$merge_sha" | grep -Eq '^[0-9a-fA-F]{40}$'; then
        merge_sha="$(printf '%s' "$merge_sha" | tr 'A-F' 'a-f')"
        json_out "$repository" "$pr_number" "$pr_url" "MERGED" "AVAILABLE" "$merged_at" "$merge_sha" "github"
        exit 0
      fi
      json_out "$repository" "$pr_number" "$pr_url" "MERGED" "UNAVAILABLE" "$merged_at" "" "github"
      exit 2
    fi
    case "$state" in
      OPEN)   json_out "$repository" "$pr_number" "$pr_url" "OPEN" "NOT_MERGED" "" "" "github"; exit 0 ;;
      CLOSED) json_out "$repository" "$pr_number" "$pr_url" "CLOSED" "NOT_MERGED" "" "" "github"; exit 0 ;;
      *)      json_out "$repository" "$pr_number" "$pr_url" "UNKNOWN" "UNAVAILABLE" "" "" "github"; exit 2 ;;
    esac
  fi
  err_text="$(cat "$gh_err")"
  # A definite target-PR 404 is not an offline condition and must not consult local history.
  if printf '%s' "$err_text" | grep -Eqi 'HTTP 404|Could not resolve to a PullRequest|pull request not found'; then
    json_out "$repository" "$pr_number" "$pr_url" "UNKNOWN" "UNAVAILABLE" "" "" "none"
    exit 2
  fi
  fallback=1
fi

# Restricted local fallback: canonical remote default branch, reachable exact merge subjects, unique SHA.
if [ "$fallback" -eq 1 ]; then
  remote=""
  while IFS= read -r name; do
    url="$(git -C "$TOP" remote get-url "$name" 2>/dev/null || true)"
    case "$url" in
      https://github.com/"$repository"|https://github.com/"$repository".git|git@github.com:"$repository"|git@github.com:"$repository".git|ssh://git@github.com/"$repository"|ssh://git@github.com/"$repository".git)
        remote="$name"
        break
        ;;
    esac
  done <<EOF
$(git -C "$TOP" remote)
EOF
  default_ref=""
  [ -n "$remote" ] && default_ref="$(git -C "$TOP" symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
  candidates=""
  if [ -n "$default_ref" ] && git -C "$TOP" rev-parse --verify --quiet "$default_ref" >/dev/null; then
    candidates="$(git -C "$TOP" log "$default_ref" --merges --format='%H%x09%s' 2>/dev/null | python3 -c '
import re, sys
number = sys.argv[1]
pattern = re.compile(r"^([0-9a-fA-F]{40})\tMerge pull request #" + re.escape(number) + r" from (\S+)$")
for line in sys.stdin:
    match = pattern.match(line.rstrip("\n"))
    if match:
        print(match.group(1).lower())
' "$pr_number")"
  fi
  count="$(printf '%s\n' "$candidates" | grep -c . || true)"
  if [ "$count" -eq 1 ]; then
    json_out "$repository" "$pr_number" "$pr_url" "MERGED" "AVAILABLE" "" "$candidates" "local-git"
    exit 0
  fi
  if [ "$count" -gt 1 ]; then
    json_out "$repository" "$pr_number" "$pr_url" "UNKNOWN" "AMBIGUOUS" "" "" "none"
    exit 3
  fi
fi
json_out "$repository" "$pr_number" "$pr_url" "UNKNOWN" "UNAVAILABLE" "" "" "none"
exit 2
