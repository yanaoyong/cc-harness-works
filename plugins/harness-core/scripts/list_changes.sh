#!/usr/bin/env bash
# 列出 .harness/changes/ 下所有变更目录及其需求名称、中文描述、原始请求、状态、阶段。
# 用法:
#   bash .harness/scripts/list_changes.sh                  # 默认 --all，仅 stdout
#   bash .harness/scripts/list_changes.sh --all|--active|--closed|--exempt
#   bash .harness/scripts/list_changes.sh --write          # 默认 --all + 刷新 INDEX.md
#   bash .harness/scripts/list_changes.sh --active --write # 过滤器与 --write 可组合
# 字段来源: 各 summary.md 头部（需求名称 / 中文描述 / 原始请求 / 总体状态 / 当前阶段）。
# 归类逻辑见 .harness/scripts/list_flows.sh classify_bucket() 与本文件 classify()（两者口径一致）:
#   1. strip 状态值的 ** 修饰字符（本文件 PARSE_AWK END 段剥 * 处理）
#   2. {{占位}} / A_R1_CODE_ONLY* → 异常豁免档
#   3. PASSED + stage 以 10 起始 → 闭合档（前缀匹配 · 容忍「10（…）」等后缀 · R-8 归类放宽）
#   4. 其余 → 活跃档
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
INDEX_FILE="$ROOT/.harness/changes/INDEX.md"

filter="--all"
write_index=0
for arg in "$@"; do
  case "$arg" in
    --all|--active|--closed|--exempt) filter="$arg" ;;
    --write) write_index=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown arg: $arg (use --all|--active|--closed|--exempt [--write])" >&2
      exit 2
      ;;
  esac
done

# ---------- summary.md 5 字段单遍 awk 提取（与 list_flows.sh PARSE_AWK 同模式 · T2）----------
# 解析语义与原 extract_cell 逐字段冻结一致：
#   - 取首个含 `| <key> |` 子串的行（原 grep -m1 语义），FS='|' 第 3 列两端 [[:space:]] trim；
#   - 仅 总体状态 值剥 `*` 修饰（原 sed 's/\*//g'）；
#   - 文件不可读 / 未匹配 → 字段为空（原 `|| true` 容忍语义）。
PARSE_AWK='
function trim(s) { gsub(/^[[:space:]]+/, "", s); gsub(/[[:space:]]+$/, "", s); return s }
BEGIN {
  FS = "|"
  n = split("需求名称 中文描述 原始请求 总体状态 当前阶段", key, " ")
}
{
  for (i = 1; i <= n; i++)
    if (!(i in seen) && index($0, "| " key[i] " |") > 0) { seen[i] = 1; val[i] = trim($3) }
}
END {
  s = val[4]; gsub(/\*/, "", s); val[4] = s
  for (i = 1; i <= n; i++) print val[i]
}
'

# parse_summary <file>：单次 awk 填充 req/desc/orig/state/stage 全局变量
parse_summary() {
  local out line
  out="$(awk "$PARSE_AWK" "$1" 2>/dev/null || true)"
  local -a F=()
  # bash 3.2 兼容：mapfile -t 等价改写（末行无换行守护：read 失败但 line 非空仍收录）
  while IFS= read -r line || [ -n "$line" ]; do
    F+=("$line")
  done <<<"$out"
  req="${F[0]:-}"; desc="${F[1]:-}"; orig="${F[2]:-}"
  state="${F[3]:-}"; stage="${F[4]:-}"
}

is_placeholder_strict() {
  # 仅匹配 {{...}} 形式（用于自由文本字段：中文描述/原始请求），避免误伤含"占位"二字的合法文本
  [[ "$1" == *'{{'* ]]
}

is_placeholder_loose() {
  # 匹配 {{ 或 占位 字样（用于结构字段：状态/阶段），与 hook L85-89 对齐
  [[ "$1" == *'{{'* || "$1" == *占位* ]]
}

classify() {
  local state="$1" stage="$2"
  if is_placeholder_loose "$state" || is_placeholder_loose "$stage"; then echo exempt; return; fi
  case "$state" in
    A_R1_CODE_ONLY*|*CODE_ONLY*) echo exempt; return ;;
    ABANDONED) echo exempt; return ;;  # 遗弃卡归异常/模板档（与 list_flows.sh classify_bucket 对齐）
  esac
  # R-8 归类放宽：stage 以 "10" 起始（允许任意后缀）→ closed；其余 PASSED 形态仍 active
  if [ "$state" = "PASSED" ]; then
    case "$stage" in
      10*) echo closed; return ;;
    esac
  fi
  echo active
}

truncate_str() {
  # truncate_str <str> <max-len>，超出加 …
  local s="$1" max="$2"
  if [ "${#s}" -le "$max" ]; then printf '%s' "$s"; else printf '%s…' "${s:0:$((max-1))}"; fi
}

shopt -s nullglob
declare -i count_total=0 count_active=0 count_closed=0 count_exempt=0
stdout_rows=""
index_sections=""

for d in "$ROOT"/.harness/changes/*/; do
  name=$(basename "$d")
  [ "$name" = "_TEMPLATE" ] && continue
  summary="$d/summary.md"
  [ -f "$summary" ] || continue

  parse_summary "$summary"

  # 缺字段或 {{占位}} → 显示 <未填>
  # 结构字段 state/stage 用 loose（保留对"占位"字样的拦截，与 hook 对齐）
  # 自由文本 req/desc/orig 用 strict（仅拦 {{...}}，允许内容含"占位"二字）
  for var in state stage; do
    val="${!var}"
    if [ -z "$val" ] || is_placeholder_loose "$val"; then
      eval "$var='<未填>'"
    fi
  done
  for var in req desc orig; do
    val="${!var}"
    if [ -z "$val" ] || is_placeholder_strict "$val"; then
      eval "$var='<未填>'"
    fi
  done

  bucket=$(classify "$state" "$stage")
  count_total+=1
  case "$bucket" in
    active) count_active+=1 ;;
    closed) count_closed+=1 ;;
    exempt) count_exempt+=1 ;;
  esac

  show=0
  case "$filter" in
    --all) show=1 ;;
    --active) [ "$bucket" = "active" ] && show=1 ;;
    --closed) [ "$bucket" = "closed" ] && show=1 ;;
    --exempt) [ "$bucket" = "exempt" ] && show=1 ;;
  esac
  [ "$show" = "0" ] && continue

  desc_short=$(truncate_str "$desc" 24)
  stdout_rows+="$(printf '%-50s  %-22s  %-24s  %-12s  stage=%-3s  [%s]' "$name" "$req" "$desc_short" "$state" "$stage" "$bucket")"$'\n'

  index_sections+="### \`$name\` · [$bucket]"$'\n\n'
  index_sections+="- **英文 slug**：$req"$'\n'
  index_sections+="- **中文描述**：$desc"$'\n'
  index_sections+="- **原始请求**：$orig"$'\n'
  index_sections+="- **状态 / 阶段**：$state · stage=$stage"$'\n\n'
done

printf '%-50s  %-22s  %-24s  %-12s  %-9s  %s\n' "目录" "英文 slug" "中文描述" "状态" "阶段" "归类"
printf '%-50s  %-22s  %-24s  %-12s  %-9s  %s\n' "----" "---------" "--------" "----" "----" "----"
printf '%s' "$stdout_rows"
echo
echo "汇总（过滤器: ${filter}）：活跃 ${count_active} · 闭合 ${count_closed} · 异常/模板 ${count_exempt} · 合计 ${count_total}"

if [ "$write_index" = "1" ]; then
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  {
    echo "# 变更目录索引（INDEX）"
    echo
    echo "> **自动生成 · 禁止手改**。由 \`bash .harness/scripts/list_changes.sh --write\` 刷新；手动修改本文件会在下次 \`--write\` 时被覆盖。"
    echo "> 数据源：各 \`.harness/changes/<dir>/summary.md\` 头部表（需求名称 / 中文描述 / 原始请求 / 总体状态 / 当前阶段）。"
    echo "> 归类逻辑见 \`.harness/scripts/list_flows.sh classify_bucket()\` 与 \`.harness/scripts/list_changes.sh classify()\`（本脚本）。"
    echo "> 生成时间：$ts · 过滤器：\`$filter\`"
    echo
    echo "## 汇总"
    echo
    echo "- 活跃 **${count_active}** · 闭合 **${count_closed}** · 异常/模板 **${count_exempt}** · 合计 **${count_total}**"
    echo
    echo "## 明细"
    echo
    printf '%s' "$index_sections"
  } > "$INDEX_FILE"
  echo
  echo "✅ 已刷新 $INDEX_FILE"
fi
