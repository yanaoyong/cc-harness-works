#!/usr/bin/env bash
# list_flows.sh —— stage-02 升级版流程实例清单工具（list_changes.sh 的升级版 · 后者保留不动）。
# 同时处理元流程实例（proj-*）与 10 阶段变更实例（feat-/fix-/chore-），并可刷新 project/DASHBOARD.md 人读视图。
#
# 用法:
#   bash .harness/scripts/list_flows.sh [--all|--active|--closed|--exempt] [--format=plain|json|brief] [--write]
#     --all              全部流程实例（默认）
#     --active           仅 IN_PROGRESS / REOPENED
#     --closed           仅闭合：state==PASSED 且无 REOPENED/BLOCKED 子项；10 阶段还需 stage 以 10 起始，元流程需 M5 起始 PASSED
#     --exempt           异常/模板：_* 模板目录 / ABANDONED / {{占位}} / *CODE_ONLY* 异常豁免
#     --format=plain     文本分组表（默认 · 用户读）
#     --format=brief     精简聚合行（hook 注入用 · --active 空集时 stdout 为空）
#     --format=json      机器可读 JSON（schema 见 spec FR-5）
#     --write            同时刷新 project/DASHBOARD.md（聚合视图 · 自动生成勿手改；project/ 不存在时 mkdir -p）
#   过滤器与 --format / --write 可任意组合；-h|--help 输出本用法。
#
# 纪律（D-02 §4）:
#   - 只读状态来源（summary.md / cascade_evaluations/ / integration/），不写任何状态来源
#   - 唯一写目标 = project/DASHBOARD.md（聚合视图 · 非 SSOT）
#   - 单文件解析失败容忍：stderr warning + 跳过，不阻塞其他实例；正常路径退出码 0、参数错误 2
#   - L 通道任何数据不进本工具输出与 DASHBOARD 主表
#
# 解析（D-02 §2.4 · D-P1 §7 · 双格式兼容 · HITL-1 P-3）:
#   (a) stage-01 中文标签表行（| 总体状态 | / | 当前阶段 |，剥 ** 修饰、识别 {{占位}}）
#   (b) 英文字段名（proj-* 实例 · 卡 3 _PROJ_TEMPLATE 接口约定）：表行 `| state | x |` 或键值行 `state: x`
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
CHANGES_DIR="$ROOT/.harness/changes"
DASHBOARD_FILE="$ROOT/project/DASHBOARD.md"

# FR-5 merged 判定单点（lib/merged_detect.sh · 三处共享 · 防双源漂移）。
# 仅 --active 输出过滤需要它（排除"PR 已合并"的卡）；缺失则 merged 函数不可用，
# --active 退化为不排除（保守 · 不阻断其它路径）。MF-2：不污染 classify_bucket 与其它路径。
_MD_LIB="$ROOT/.harness/scripts/lib/merged_detect.sh"
# shellcheck source=/dev/null
[ -r "$_MD_LIB" ] && . "$_MD_LIB"

filter="--all"
format="plain"
write_dashboard=0
for arg in "$@"; do
  case "$arg" in
    --all|--active|--closed|--exempt) filter="$arg" ;;
    --format=plain|--format=json|--format=brief) format="${arg#--format=}" ;;
    --write) write_dashboard=1 ;;
    -h|--help)
      # 输出脚本头注释块（shebang 之后至首个非注释行为止 · 无行号硬耦合）
      awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $arg (use [--all|--active|--closed|--exempt] [--format=plain|json|brief] [--write])" >&2
      exit 2
      ;;
  esac
done

warn() { printf 'warning: %s\n' "$1" >&2; }

# ---------- 级联评估 / 联调追踪 frontmatter status 过滤（chore-cascade-eval-schema）----------
# _fm_status <file>：从首个 frontmatter（---…---）区块内提取 `status:` 值（去空格 · 小写）。
# bash 3.2 兼容：纯 awk 解析，无关联数组 / 无 bash4 语法。与 hook user_prompt_state_inject.sh 口径一致。
# 缺失 / 无 frontmatter / 解析失败 → 空串（调用方按未闭合计入 · 保守暴露）。
_fm_status() {
  awk '
    NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR==1 { infm=1; next }
    infm && $0 ~ /^---[[:space:]]*$/ { exit }
    infm && $0 ~ /^[[:space:]]*status[[:space:]]*:/ {
      sub(/^[[:space:]]*status[[:space:]]*:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print tolower($0); exit
    }
  ' "$1" 2>/dev/null
}

# _fm_is_resolved <file>：status ∈ {resolved,closed,done} → 0（已闭合 · 过滤掉）；否则 1（计入）
_fm_is_resolved() {
  case "$(_fm_status "$1")" in
    resolved|closed|done) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------- 前缀归类（D-04 §2/§4.2）----------
classify_prefix() {
  # $1 = 目录名；echo meta|ten-stage|exempt|unknown
  local name="$1"
  case "$name" in
    proj-init-*|proj-module-*|proj-arch-*|proj-revision-*) echo meta ;;
    feat-*|fix-*|chore-*) echo ten-stage ;;
    _*) echo exempt ;;
    *) echo unknown ;;
  esac
}

# ---------- summary.md 双格式字段解析（FR-3 · 单遍 awk 提取全部 11 字段 + 子项标志）----------
# 解析语义与原 field_cn/field_en/field_dual 逐字段冻结一致：
#   - 仅 总体状态/state、当前阶段/current_stage 两字段中文标签优先（首个中文表行且值非空）
#     → 英文表行 → 英文键值行回退；该两字段值剥 `**` 修饰；
#   - 其余 9 字段仅英文双体例：表行 `| key | v |`（存在匹配行即取第 2 列，含空值）优先于键值行 `key: v`；
#   - 各通道分别取首个匹配行（原 grep -m1 语义）；表行第 2 列 / 键值行值两端 [[:space:]] trim。
is_placeholder_loose() { [[ "$1" == *'{{'* || "$1" == *占位* ]]; }

PARSE_AWK='
function trim(s) { gsub(/^[[:space:]]+/, "", s); gsub(/[[:space:]]+$/, "", s); return s }
function en_val(k) { if (k in tf) return tv[k]; if (k in kf) return kvv[k]; return "" }
function out_en(k) { print en_val(k) }
function out_dual(c, k,    v) {
  v = ((c in cn) && cn[c] != "") ? cn[c] : en_val(k)
  gsub(/\*/, "", v)
  print v
}
BEGIN {
  FS = "|"
  split("state current_stage m3_substage last_progress_time pending_notes " \
        "trigger_mode source reason bug_class parent_change_dir roadmap_card_id " \
        "m0_5_state m0_5_decision", a, " ")
  for (i in a) ek[a[i]] = 1
}
/^\|/ {
  if (NF >= 3) {
    k = trim($2); v = trim($3)
    if ((k == "总体状态" || k == "当前阶段") && !(k in cn)) cn[k] = v
    if ((k in ek) && !(k in tf)) { tf[k] = 1; tv[k] = v }
    # 阶段记录表 REOPENED / BLOCKED 子项（排除头部"总体状态/state"字段行）→ open=1
    c1 = $2; c3 = $3
    gsub(/[[:space:]*]/, "", c1); gsub(/[[:space:]*]/, "", c3)
    if (c1 != "总体状态" && c1 != "state" && (c3 == "REOPENED" || c3 == "BLOCKED")) open = 1
  }
  next
}
{
  p = index($0, ":")
  if (p > 0) {
    k = trim(substr($0, 1, p - 1))
    if ((k in ek) && !(k in kf)) { kf[k] = 1; kvv[k] = trim(substr($0, p + 1)) }
  }
}
END {
  out_dual("总体状态", "state")
  out_dual("当前阶段", "current_stage")
  out_en("m3_substage"); out_en("last_progress_time"); out_en("pending_notes")
  out_en("trigger_mode"); out_en("source"); out_en("reason"); out_en("bug_class")
  out_en("parent_change_dir"); out_en("roadmap_card_id")
  out_en("m0_5_state"); out_en("m0_5_decision")
  print (open ? 1 : 0)
}
'

# parse_summary <file>：单次 awk 填充 g_* 全局变量（含 g_open_sub 子项标志）；文件不可读返回 1
parse_summary() {
  local f="$1" out line
  g_state="" g_stage="" g_m3="" g_lpt="" g_notes="" g_trigger=""
  g_source="" g_reason="" g_bug_class="" g_parent="" g_rmcard=""
  g_m0_5_state="" g_m0_5_decision="" g_open_sub=0
  [ -r "$f" ] || return 1
  out="$(awk "$PARSE_AWK" "$f" 2>/dev/null || true)"
  local -a F=()
  # bash 3.2 兼容：mapfile -t 等价改写（末行无换行守护：read 失败但 line 非空仍收录）
  while IFS= read -r line || [ -n "$line" ]; do
    F+=("$line")
  done <<<"$out"
  g_state="${F[0]:-}"; g_stage="${F[1]:-}"; g_m3="${F[2]:-}"; g_lpt="${F[3]:-}"
  g_notes="${F[4]:-}"; g_trigger="${F[5]:-}"; g_source="${F[6]:-}"; g_reason="${F[7]:-}"
  g_bug_class="${F[8]:-}"; g_parent="${F[9]:-}"; g_rmcard="${F[10]:-}"
  g_m0_5_state="${F[11]:-}"; g_m0_5_decision="${F[12]:-}"
  g_open_sub="${F[13]:-0}"
  return 0
}

# ---------- 4 档判定（FR-4）----------
classify_bucket() {
  # $1=group $2=state $3=stage $4=REOPENED/BLOCKED 子项标志（1=存在 · parse_summary g_open_sub）；echo active|closed|exempt|other
  local group="$1" state="$2" stage="$3" open_sub="${4:-0}"
  if [ "$group" = "exempt" ]; then echo exempt; return; fi
  if is_placeholder_loose "$state" || is_placeholder_loose "$stage"; then echo exempt; return; fi
  case "$state" in
    *CODE_ONLY*) echo exempt; return ;;
    ABANDONED) echo exempt; return ;;
    IN_PROGRESS|REOPENED) echo active; return ;;
  esac
  if [ "$state" = "PASSED" ]; then
    if [ "$open_sub" = "1" ]; then echo other; return; fi
    # R-8 归类放宽：stage 以 M5 / 10 起始（允许任意后缀）→ closed；组归属判定不变
    if [ "$group" = "meta" ]; then
      case "$stage" in M5*) echo closed; return ;; esac
    else
      case "$stage" in 10*) echo closed; return ;; esac
    fi
    echo other; return
  fi
  echo other
}

# ---------- 命名歧义检测（FR-9 · 只 warning 不交互）----------
check_naming() {
  # $1=目录名 $2=group
  local name="$1" group="$2"
  if [ "$group" = "unknown" ]; then
    warn "未注册前缀: ${name}（已归入 unknown · 前缀注册表见 docs/stage-02 D-04 §2）"
  fi
  if [[ "$name" =~ [[:space:]] ]] || ! [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    warn "目录名含禁用字符（中文/空格/特殊字符）: $name"
  fi
}

# ---------- 扫描 ----------
shopt -s nullglob
declare -a A_name=() A_group=() A_bucket=() A_state=() A_stage=() A_m3=() A_lpt=() A_notes=()
declare -a A_trigger=() A_source=() A_reason=() A_bug=() A_parent=() A_rmcard=() A_mtime=()
declare -a A_m05=() A_m05dec=()
# bash 3.2 兼容：关联数组 → 平行数组线性查找（base → date_part；N 为实例数，线性可接受）
declare -a SLUG_BASES=() SLUG_DATES=()

slug_suffix_re='-[0-9]{8}(-r[0-9]+)?$'
date_run_re='[0-9]{8}'

# ---------- --active 热路径锚定预筛（机制 W · 仅 --active 且非 --write 时启用）----------
# 先用一次 grep -lE 锚定 state 载体行（CN 总体状态表行 / EN state 表行 / EN state 键值行 ·
# 不含 $ 兼容 CRLF）得候选目录集，扫描循环只遍历候选目录；其余跳过不 parse。
# 正确性：锚定与 classify_bucket 的 active 判据同三载体同值集 → 预筛集 ⊇ 真实活跃集（无漏判），
# 过包含由 classify_bucket 兜底滤除。--all/--closed/--exempt 及 --write 走全量扫描（语义零变化）。
# --write 需全量数据刷 DASHBOARD（render_dashboard 不受过滤器影响），故 --active --write 不走预筛。
prefilter_active=0
declare -a SCAN_DIRS=()
if [ "$filter" = "--active" ] && [ "$write_dashboard" = "0" ] && [ -d "$CHANGES_DIR" ]; then
  prefilter_active=1
  active_state_re='^\| *(总体状态|state) *\| *\**(IN_PROGRESS|REOPENED)\**|^state *: *\**(IN_PROGRESS|REOPENED)\**'
  while IFS= read -r _cand; do
    [ -n "$_cand" ] && SCAN_DIRS+=("${_cand%summary.md}")
  done < <(grep -lE "$active_state_re" "$CHANGES_DIR"/*/summary.md 2>/dev/null || true)
else
  # 全量扫描路径：保留原 glob 语义（nullglob 已开 · 无目录则 SCAN_DIRS 为空）
  [ -d "$CHANGES_DIR" ] && SCAN_DIRS=("$CHANGES_DIR"/*/)
fi

if [ -d "$CHANGES_DIR" ]; then
  for d in ${SCAN_DIRS[@]+"${SCAN_DIRS[@]}"}; do
    name="${d%/}"; name="${name##*/}"
    group="$(classify_prefix "$name")"
    check_naming "$name" "$group"

    # 同 slug 跨日重复检测（FR-9）：剥掉 -YYYYMMDD（及 -rN 修订后缀）后聚合
    base="$name"
    if [[ "$name" =~ $slug_suffix_re ]]; then
      base="${name%"${BASH_REMATCH[0]}"}"
    fi
    # 取目录名中最后一段 8 位数字（原 grep -oE '[0-9]{8}' | tail -1 的非重叠最后匹配语义）
    date_part=""
    rest="$name"
    while [[ "$rest" =~ $date_run_re ]]; do
      date_part="${BASH_REMATCH[0]}"
      rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
    if [ -n "$date_part" ] && [ "$base" != "$name" ]; then
      prev=""; slug_idx=-1
      for ((j = 0; j < ${#SLUG_BASES[@]}; j++)); do
        if [ "${SLUG_BASES[$j]}" = "$base" ]; then prev="${SLUG_DATES[$j]}"; slug_idx=$j; break; fi
      done
      if [ -n "$prev" ] && [ "$prev" != "$date_part" ]; then
        warn "同 slug 跨日重复: ${base}（$prev 与 ${date_part}）"
      fi
      if [ "$slug_idx" -ge 0 ]; then
        SLUG_DATES[$slug_idx]="$date_part"
      else
        SLUG_BASES+=("$base"); SLUG_DATES+=("$date_part")
      fi
    fi

    summary="$d/summary.md"
    if [ "$group" = "exempt" ]; then
      # _* 模板目录：不要求 summary.md
      A_name+=("$name"); A_group+=("exempt"); A_bucket+=("exempt")
      A_state+=("模板"); A_stage+=("—"); A_m3+=(""); A_lpt+=(""); A_notes+=("")
      A_trigger+=(""); A_source+=(""); A_reason+=(""); A_bug+=(""); A_parent+=(""); A_rmcard+=("")
      A_m05+=(""); A_m05dec+=("")
      A_mtime+=("$(stat -c '%Y' "$d" 2>/dev/null || echo 0)")
      continue
    fi

    if [ ! -f "$summary" ]; then
      warn "缺少 summary.md，跳过: $name"
      continue
    fi
    if ! parse_summary "$summary"; then
      warn "summary.md 解析失败，跳过: $name"
      continue
    fi
    if [ -z "$g_state" ] && [ -z "$g_stage" ]; then
      # 双格式均未解析出 state / current_stage → 视为坏格式（FR-3 失败容忍：warning + 跳过，不阻塞其他）
      warn "summary.md 坏格式（state/current_stage 均不可解析），跳过: $name"
      continue
    fi

    bucket="$(classify_bucket "$group" "$g_state" "$g_stage" "$g_open_sub")"
    A_name+=("$name"); A_group+=("$group"); A_bucket+=("$bucket")
    A_state+=("$g_state"); A_stage+=("$g_stage"); A_m3+=("$g_m3"); A_lpt+=("$g_lpt"); A_notes+=("$g_notes")
    A_trigger+=("$g_trigger"); A_source+=("$g_source"); A_reason+=("$g_reason")
    A_bug+=("$g_bug_class"); A_parent+=("$g_parent"); A_rmcard+=("$g_rmcard")
    A_m05+=("$g_m0_5_state"); A_m05dec+=("$g_m0_5_decision")
    A_mtime+=("$(stat -c '%Y' "$summary" 2>/dev/null || echo 0)")
  done
else
  warn "未定位到 $CHANGES_DIR"
fi

total=${#A_name[@]}

# ---------- 过滤 ----------
# --active merged 排除（fix-autoflip-oq3 · 方案 A 动作①）：
#   对判为 active 的卡额外调 merged_detect_sha 排除"PR 已合并进 main"的卡——R4 消噪在检测层、
#   零 mutation 零分叉。MF-2 边界：仅 --active 输出过滤；不动 classify_bucket（卡 bucket 仍按
#   总体状态判 active）、不动 --all/--closed/--exempt/--json/--write/DASHBOARD（它们照常列出该卡）。
#   热路径（OQ-4/MF-1）：merged_detect_sha 只对 active-bucket 卡跑（机制 W 预筛后 total 已是活跃
#   候选小集），git log 调用次数 == active 候选数、不随总卡数增长。
#   降级：merged_detect_sha 未 source（lib 缺）→ type 检测失败 → 不排除（保守列出 · 不阻断）。
declare -a SEL=()
for ((i = 0; i < total; i++)); do
  case "$filter" in
    --all) SEL+=("$i") ;;
    --active)
      if [ "${A_bucket[$i]}" = "active" ]; then
        if type merged_detect_sha >/dev/null 2>&1 && merged_detect_sha "${A_name[$i]}" >/dev/null 2>&1; then
          : # PR 已合并 → 不计入 --active 输出（R4 消噪）
        else
          SEL+=("$i")
        fi
      fi
      ;;
    --closed) [ "${A_bucket[$i]}" = "closed" ] && SEL+=("$i") ;;
    --exempt) [ "${A_bucket[$i]}" = "exempt" ] && SEL+=("$i") ;;
  esac
done

dash() { [ -n "$1" ] && printf '%s' "$1" || printf '—'; }

stage_disp() {
  # $1=group $2=stage：ten-stage 数字 → "阶段 N"；meta 主列只显示 M0–M5
  local group="$1" stage="$2"
  [ -z "$stage" ] && { printf '—'; return; }
  if [ "$group" = "ten-stage" ] || [ "$group" = "unknown" ]; then
    if [[ "$stage" =~ ^[0-9]+$ ]]; then printf '阶段 %s' "$stage"; return; fi
  fi
  printf '%s' "$stage"
}

substage_paren() {
  # $1=stage $2=m3_substage：仅 M3 且 substage 非空时输出括注
  if [ "$1" = "M3" ] && [ -n "$2" ]; then printf '（m3_substage: %s）' "$2"; fi
}

m0_5_paren() {
  # $1=m0_5_state：实例 m0_5_state 非空时输出括注（独立阶段位标签 · 类比 substage_paren M3 范式）
  # 供 hook 渲染层据此产出"下一步"提示（OQ-1 方案 A：list_flows 为唯一解析/暴露源）。
  if [ -n "$1" ]; then printf '（m0_5: %s）' "$1"; fi
}

# ---------- format=plain ----------
render_plain() {
  local -a g_meta=() g_ten=() g_exempt=() g_unknown=()
  local i
  for i in ${SEL[@]+"${SEL[@]}"}; do
    case "${A_group[$i]}" in
      meta) g_meta+=("$i") ;;
      ten-stage) g_ten+=("$i") ;;
      exempt) g_exempt+=("$i") ;;
      unknown) g_unknown+=("$i") ;;
    esac
  done

  plain_section "== 元流程实例（meta · ${#g_meta[@]}）==" "${g_meta[@]:-}"
  echo
  plain_section "== 10 阶段变更实例（ten-stage · ${#g_ten[@]}）==" "${g_ten[@]:-}"
  echo
  plain_section "== 异常/模板（exempt · ${#g_exempt[@]}）==" "${g_exempt[@]:-}"
  if [ "${#g_unknown[@]}" -gt 0 ]; then
    echo
    plain_section "== 未注册前缀（unknown · ${#g_unknown[@]}）==" "${g_unknown[@]:-}"
  fi
}

plain_section() {
  local title="$1"; shift
  echo "$title"
  local i notes
  for i in "$@"; do
    [ -z "$i" ] && continue
    if [ "${A_group[$i]}" = "exempt" ]; then
      printf '%-42s  %s\n' "${A_name[$i]}" "模板"
      continue
    fi
    notes="$(dash "${A_notes[$i]}")$(substage_paren "${A_stage[$i]}" "${A_m3[$i]}")$(m0_5_paren "${A_m05[$i]}")"
    printf '%-42s  %-8s  %-12s  %-12s  %s\n' \
      "${A_name[$i]}" "$(stage_disp "${A_group[$i]}" "${A_stage[$i]}")" \
      "$(dash "${A_state[$i]}")" "$(dash "${A_lpt[$i]}")" "$notes"
  done
}

# ---------- format=brief（hook 注入用 · --active 空集时 stdout 必须为空）----------
render_brief() {
  local group state i item j found
  # bash 3.2 兼容：关联数组 → 平行数组（bs_keys/bs_vals · 首现序确定性输出）
  local -a bs_keys=() bs_vals=() passed_names=()
  for group in meta ten-stage exempt unknown; do
    # 非 PASSED 状态逐项；PASSED 聚合计数
    bs_keys=(); bs_vals=()
    passed_names=()
    for i in ${SEL[@]+"${SEL[@]}"}; do
      [ "${A_group[$i]}" = "$group" ] || continue
      if [ "$group" = "exempt" ]; then
        passed_names+=("${A_name[$i]}")
        continue
      fi
      state="$(dash "${A_state[$i]}")"
      if [ "$state" = "PASSED" ]; then
        passed_names+=("${A_name[$i]}")
        continue
      fi
      item="${A_name[$i]} · $(stage_disp "$group" "${A_stage[$i]}")$(substage_paren "${A_stage[$i]}" "${A_m3[$i]}")$(m0_5_paren "${A_m05[$i]}")"
      found=-1
      for ((j = 0; j < ${#bs_keys[@]}; j++)); do
        if [ "${bs_keys[$j]}" = "$state" ]; then found=$j; break; fi
      done
      if [ "$found" -ge 0 ]; then
        bs_vals[$found]="${bs_vals[$found]} / $item"
      else
        bs_keys+=("$state"); bs_vals+=("$item")
      fi
    done
    for state in IN_PROGRESS REOPENED; do
      for ((j = 0; j < ${#bs_keys[@]}; j++)); do
        if [ "${bs_keys[$j]}" = "$state" ]; then echo "${group}[${state}]: ${bs_vals[$j]}"; fi
      done
    done
    for ((j = 0; j < ${#bs_keys[@]}; j++)); do
      state="${bs_keys[$j]}"
      case "$state" in IN_PROGRESS|REOPENED) continue ;; esac
      echo "${group}[${state}]: ${bs_vals[$j]}"
    done
    if [ "${#passed_names[@]}" -gt 0 ]; then
      local joined
      joined="$(printf '%s / ' "${passed_names[@]}")"; joined="${joined% / }"
      if [ "$group" = "exempt" ]; then
        echo "exempt: ${#passed_names[@]} 个（${joined}）"
      else
        echo "${group}[PASSED]: ${#passed_names[@]} 个（${joined}）"
      fi
    fi
  done
}

# ---------- format=json ----------
json_escape() {
  # 纯 bash 等价改写（原 sed 转义 \ → " → tab，再 tr 删 \n\r；逐字节语义不变）
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/}"
  s="${s//$'\r'/}"
  printf '%s' "$s"
}

json_str_or_null() {
  if [ -n "$1" ]; then printf '"%s"' "$(json_escape "$1")"; else printf 'null'; fi
}

render_json() {
  local i first=1
  local c_meta=0 c_ten=0 c_exempt=0 c_unknown=0
  printf '{\n  "generated_at": "%s",\n  "filter": "%s",\n  "instances": [' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$filter"
  for i in ${SEL[@]+"${SEL[@]}"}; do
    case "${A_group[$i]}" in
      meta) c_meta=$((c_meta + 1)) ;;
      ten-stage) c_ten=$((c_ten + 1)) ;;
      exempt) c_exempt=$((c_exempt + 1)) ;;
      unknown) c_unknown=$((c_unknown + 1)) ;;
    esac
    [ "$first" = "1" ] && first=0 || printf ','
    printf '\n    {"name": "%s", "group": "%s", "state": %s, "stage": %s, "m3_substage": %s, "trigger_mode": %s, "last_progress_time": %s, "pending_notes": %s, "source": %s}' \
      "$(json_escape "${A_name[$i]}")" "${A_group[$i]}" \
      "$(json_str_or_null "${A_state[$i]}")" "$(json_str_or_null "${A_stage[$i]}")" \
      "$(json_str_or_null "${A_m3[$i]}")" "$(json_str_or_null "${A_trigger[$i]}")" \
      "$(json_str_or_null "${A_lpt[$i]}")" "$(json_str_or_null "${A_notes[$i]}")" \
      "$(json_str_or_null "${A_source[$i]}")"
  done
  printf '\n  ],\n  "counts": {"meta": %d, "ten_stage": %d, "exempt": %d, "unknown": %d, "total": %d}\n}\n' \
    "$c_meta" "$c_ten" "$c_exempt" "$c_unknown" "${#SEL[@]}"
}

# ---------- --write 刷 project/DASHBOARD.md（FR-6 · 全量数据 · 不受过滤器影响）----------
trigger_disp() {
  case "$1" in
    A) printf 'A · First-Run' ;;
    B) printf 'B · Module-Init' ;;
    C) printf 'C · Arch-Evolve' ;;
    D) printf 'D · Re-Vision' ;;
    E) printf 'E · Phase-Revise' ;;
    "") printf '—' ;;
    *) printf '%s' "$1" ;;
  esac
}

sort_key_epoch() {
  # $1=last_progress_time $2=mtime → epoch（lpt 缺失/不可解析回退 mtime）
  local lpt="$1" mtime="$2" epoch=""
  if [ -n "$lpt" ] && [ "$lpt" != "—" ]; then
    epoch="$(date -d "$lpt" '+%s' 2>/dev/null || true)"
  fi
  [ -n "$epoch" ] && printf '%s' "$epoch" || printf '%s' "$mtime"
}

render_dashboard() {
  mkdir -p "$ROOT/project"
  local i ts
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"

  local -a act_meta=() act_rm=() act_adhoc=() act_fix=() closed_idx=()
  for ((i = 0; i < total; i++)); do
    if [ "${A_bucket[$i]}" = "active" ]; then
      if [ "${A_group[$i]}" = "meta" ]; then
        act_meta+=("$i")
      elif [ "${A_group[$i]}" = "ten-stage" ]; then
        if [ "${A_source[$i]}" = "roadmap-driven" ]; then
          act_rm+=("$i")
        elif [ "${A_source[$i]}" = "fix" ] || [[ "${A_name[$i]}" == fix-* ]]; then
          act_fix+=("$i")
        else
          # source 缺失的存量变更归 ad-hoc · reason 填 —（spec FR-6 v1.1）
          act_adhoc+=("$i")
        fi
      fi
    elif [ "${A_bucket[$i]}" = "closed" ]; then
      closed_idx+=("$i")
    fi
  done

  # 级联评估（按 frontmatter status 过滤未 resolved · schema 已定稿见机制文档 §4.4）
  local -a eval_files=()
  for f in "$CHANGES_DIR"/proj-*/cascade_evaluations/eval_*.md; do
    [ -r "$f" ] || { warn "级联评估文件不可读，跳过: $f"; continue; }
    _fm_is_resolved "$f" && continue   # 已闭合级联 → 不列入"待处理"
    eval_files+=("$f")
  done
  # 联调追踪（按 frontmatter status 过滤未关闭 · 顺带修 resolved mismatch 误列 bug）
  local -a mismatch_files=()
  for f in "$CHANGES_DIR"/*/integration/contract-mismatch.md; do
    [ -r "$f" ] || { warn "联调追踪文件不可读，跳过: $f"; continue; }
    _fm_is_resolved "$f" && continue   # 已 resolved 的 mismatch → 不列入"联调追踪"
    mismatch_files+=("$f")
  done

  # 最近闭合：last_progress_time 降序（缺失回退 summary.md mtime）· 取最近 5
  local -a recent_closed=()
  if [ "${#closed_idx[@]}" -gt 0 ]; then
    while IFS= read -r line; do
      recent_closed+=("${line#*$'\t'}")
    done < <(
      for i in "${closed_idx[@]}"; do
        printf '%s\t%s\n' "$(sort_key_epoch "${A_lpt[$i]}" "${A_mtime[$i]}")" "$i"
      done | sort -rn -k1,1 | head -5
    )
  fi

  {
    echo "# 项目流程 Dashboard"
    echo "> 最后刷新：$ts · 由 hook 自动维护 · 勿手动编辑"
    echo
    echo "## 活跃元流程实例（${#act_meta[@]}）"
    echo
    if [ "${#act_meta[@]}" -gt 0 ]; then
      echo "| 实例 | 触发模式 | 当前阶段 | 状态 | 上次推进 | 待续要点 |"
      echo "|---|---|---|---|---|---|"
      for i in "${act_meta[@]}"; do
        printf '| %s | %s | %s | %s | %s | %s%s |\n' \
          "${A_name[$i]}" "$(trigger_disp "${A_trigger[$i]}")" "$(dash "${A_stage[$i]}")" \
          "$(dash "${A_state[$i]}")" "$(dash "${A_lpt[$i]}")" \
          "$(dash "${A_notes[$i]}")" "$(substage_paren "${A_stage[$i]}" "${A_m3[$i]}")"
      done
    else
      echo "（无）"
    fi
    echo
    echo "## 活跃 10 阶段变更（$(( ${#act_rm[@]} + ${#act_adhoc[@]} + ${#act_fix[@]} ))）"
    echo
    echo "### roadmap-driven"
    echo
    if [ "${#act_rm[@]}" -gt 0 ]; then
      echo "| 实例 | Roadmap 卡 | 阶段 | 状态 | 上次推进 | 待续要点 |"
      echo "|---|---|---|---|---|---|"
      for i in "${act_rm[@]}"; do
        printf '| %s | %s | %s | %s | %s | %s |\n' \
          "${A_name[$i]}" "$(dash "${A_rmcard[$i]}")" "$(stage_disp ten-stage "${A_stage[$i]}")" \
          "$(dash "${A_state[$i]}")" "$(dash "${A_lpt[$i]}")" "$(dash "${A_notes[$i]}")"
      done
    else
      echo "（无）"
    fi
    echo
    echo "### ad-hoc（游离卡 · 注意是否需要回流模式 E）"
    echo
    if [ "${#act_adhoc[@]}" -gt 0 ]; then
      echo "| 实例 | reason | 阶段 | 状态 | 上次推进 |"
      echo "|---|---|---|---|---|"
      for i in "${act_adhoc[@]}"; do
        printf '| %s | %s | %s | %s | %s |\n' \
          "${A_name[$i]}" "$(dash "${A_reason[$i]}")" "$(stage_disp ten-stage "${A_stage[$i]}")" \
          "$(dash "${A_state[$i]}")" "$(dash "${A_lpt[$i]}")"
      done
    else
      echo "（无）"
    fi
    echo
    echo "### fix（bug 修复）"
    echo
    if [ "${#act_fix[@]}" -gt 0 ]; then
      echo "| 实例 | bug_class | parent | 阶段 | 状态 |"
      echo "|---|---|---|---|---|"
      for i in "${act_fix[@]}"; do
        printf '| %s | %s | %s | %s | %s |\n' \
          "${A_name[$i]}" "$(dash "${A_bug[$i]}")" "$(dash "${A_parent[$i]}")" \
          "$(stage_disp ten-stage "${A_stage[$i]}")" "$(dash "${A_state[$i]}")"
      done
    else
      echo "（无）"
    fi
    echo
    echo "## 待处理级联评估（共 ${#eval_files[@]} 项）"
    echo
    if [ "${#eval_files[@]}" -gt 0 ]; then
      for f in "${eval_files[@]}"; do
        echo "- 来自 \`$(basename "$(dirname "$(dirname "$f")")")\` · [$(basename "$f")](${f#"$ROOT"/})（status: 未 resolved，详见文件）"
      done
    else
      echo "（0 项）"
    fi
    echo
    echo "## 联调追踪（共 ${#mismatch_files[@]} 项）"
    echo
    if [ "${#mismatch_files[@]}" -gt 0 ]; then
      for f in "${mismatch_files[@]}"; do
        echo "- 来自 \`$(basename "$(dirname "$(dirname "$f")")")\` · [contract-mismatch.md](${f#"$ROOT"/})（status: 未关闭，详见文件）"
      done
    else
      echo "（0 项）"
    fi
    echo
    echo "## 最近闭合（共 ${#closed_idx[@]} 项 · 仅显示最近 5 个）"
    echo
    if [ "${#recent_closed[@]}" -gt 0 ]; then
      echo "| 实例 | 阶段 | 状态 | 上次推进 |"
      echo "|---|---|---|---|"
      for i in "${recent_closed[@]}"; do
        printf '| %s | %s | %s | %s |\n' \
          "${A_name[$i]}" "$(stage_disp "${A_group[$i]}" "${A_stage[$i]}")" \
          "$(dash "${A_state[$i]}")" "$(dash "${A_lpt[$i]}")"
      done
    else
      echo "（无）"
    fi
  } > "$DASHBOARD_FILE"
}

case "$format" in
  plain) render_plain ;;
  brief) render_brief ;;
  json) render_json ;;
esac

if [ "$write_dashboard" = "1" ]; then
  render_dashboard
  echo "✅ 已刷新 $DASHBOARD_FILE" >&2
fi

exit 0
