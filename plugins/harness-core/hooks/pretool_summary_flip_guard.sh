#!/usr/bin/env bash
# PreToolUse(Edit|Write) 守卫：拦截产出型阶段（1/3/5）summary.md 翻 PASSED 但无对应委派台账记录的
# Owner inline 逃逸（feat-hitl-authz-hardening · T4 · DF-015 · AC-8/9/10）。
#
# 契约：
#   * 注册：PreToolUse + matcher="Edit|Write|MultiEdit"（与既有 PostToolUse Edit|Write|MultiEdit 同工具面、不同生命周期，不冲突）。
#     MultiEdit 纳入（code_review_v1 M-1）：按「可用工具面之并集」防御性关闭——避免模型改用 MultiEdit 对 summary.md
#     翻 PASSED 完全绕过本门（缺口④ Owner inline 逃逸）。定界依据见 coding_report「v1 修复回路」节。
#   * 仅当 tool_input.file_path 路径归一化后匹配 .harness/changes/*/summary.md 生效（UQ-5）；否则 exit 0。
#   * 翻牌判定（阶段 1 需求分析 / 3 编码实现 / 5 单测编写 行 → PASSED）：
#       - Write：查 tool_input.content 中是否含「阶段 1/3/5 行状态 = PASSED」。
#       - Edit：查 tool_input.new_string 含该行 PASSED，且 tool_input.old_string 中该行原状态非 PASSED
#         （避免对已 PASSED 行的无关改动误拦 · B2）。
#       - MultiEdit：遍历 tool_input.edits[]，逐元素按 Edit 语义查 old_string/new_string（任一子编辑翻牌即翻牌）。
#   * 检测到翻牌 → 查 T3 委派台账（$STATE_DIR/delegations_<sid>.log · 当前会话）中该卡目录 + generator 记录；
#       - 有（同卡 generator 记录即可 · 首期宽松，阶段号能匹配更好但不强制）→ exit 0 放行。
#       - 无 → exit 2 + stderr「产出型阶段禁止 Owner inline，请委派 generator 完成后再翻牌」。
#   * 非 summary.md 路径 / 翻 N/A / 非 1/3/5 行 / M 元流程 summary（无 10 阶段记录表结构，自然不匹配行）不触发（AC-9）。
#
# AC-10 三层 fail 边界：
#   a) 规则命中（翻牌但无委派记录）→ 有意 deny。
#   b) 证据类失败（检测到翻牌后，delegations 台账缺失/不可读）→ 视同无证据 → deny（防删台账绕过硬门）。
#   c) 周边失败（payload 空/非 JSON、jq 缺失致无法解析 file_path/content）→ fail-open exit 0，不瘫痪编辑链路。
# 禁裸 set -e（AC-10）——set -uo pipefail + 逐命令容错。
set -uo pipefail

# 翻牌行正则：markdown 表行首列 = 阶段号 1/3/5（单数字，10 因「1」后接「0」非空白而被排除），次列 = PASSED。
FLIP_RE_1='\|[[:space:]]*1[[:space:]]+[^|]*\|[[:space:]]*PASSED([[:space:]]|\|)'
FLIP_RE_3='\|[[:space:]]*3[[:space:]]+[^|]*\|[[:space:]]*PASSED([[:space:]]|\|)'
FLIP_RE_5='\|[[:space:]]*5[[:space:]]+[^|]*\|[[:space:]]*PASSED([[:space:]]|\|)'

has_phase_passed() {
  # $1=文本 $2=阶段号(1/3/5)；命中返回 0
  local text="$1" ph="$2" re
  case "$ph" in
    1) re="$FLIP_RE_1" ;;
    3) re="$FLIP_RE_3" ;;
    5) re="$FLIP_RE_5" ;;
    *) return 1 ;;
  esac
  printf '%s' "$text" | grep -qE "$re" 2>/dev/null
}

# harness_state_root —— STATE_DIR 根解析单一口径（方案甲 · 锚 CLAUDE_PROJECT_DIR · 内联兜底逐字同
# lib/shell-utils.sh · feat-segmentation-and-statedir-fix-20260714 T-B）。会话中途 cwd 漂移下稳定。
if ! type harness_state_root >/dev/null 2>&1; then
  harness_state_root() {
    local top
    top="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$top" ]; then
      printf '%s\n' "$top"
      return 0
    fi
    printf '%s\n' "${CLAUDE_PROJECT_DIR:-$PWD}"
  }
fi

# ---- 寄生段退役记note（chore-hook-governance-hardening-20260715 · T-2 · AC-2.6）----
# 原「T-A2 方案 P」阶段边界记号段（SEG_FLIP_RE_2/6 / _seg_has_phase / _seg_write_marker /
# _seg_detect_and_mark 及主流程 `_seg_detect_and_mark` 调用）已整段删除。原因：该记号写入是寄生在本 T4
# 翻牌门 hook 内的旁路副作用——本门只注册 PreToolUse(Edit|Write|MultiEdit)，一旦被 Bash `sed -i` 绕过
# （sed 走 Bash 通道，本门整个不在场），记号一并静默失效 → UserPromptSubmit 分段建议永不触发（背景失效②）。
# 分段建议信号已迁往 user_prompt_state_inject.sh 的「读盘阶段号快照差分对账」（emit_stage_reconcile ·
# 快照 last_seen_stage_<sid>.log），不再依赖本门任何副作用记号。下方 1/3/5 门禁判定式（has_phase_passed /
# FLIP_RE_1/3/5 / 路径归一化 / 交叉核验 T3 委派台账 / 退出码）一字不动（AC-2.6）。

# ---- 读取 payload ----
payload=""
IFS= read -r -d '' payload || true
[ -n "$payload" ] || exit 0                       # 周边失败 → fail-open（AC-10.c）
# 快速预筛（code_review_v1 S-3 · 性能）：payload 原始串不含 `summary.md` 子串 → 目标必非 summary.md，
# 零子进程立即放行，绝大多数 Edit/Write/MultiEdit 不再起 jq。误判方向 = 「多进一次 jq」无害；
# file_path 原文含 summary.md 时才进重路径，与下方路径归一化比对严判一致。
case "$payload" in
  *summary.md*) ;;
  *) exit 0 ;;
esac
command -v jq >/dev/null 2>&1 || exit 0           # 无 jq 无法可靠解析 → fail-open（AC-10.c）

tool_name="$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null || true)"
file_path="$(jq -r '.tool_input.file_path // empty' <<<"$payload" 2>/dev/null || true)"
[ -n "$file_path" ] || exit 0

# ---- 路径归一化比对：仅 .harness/changes/<卡目录>/summary.md（UQ-5）----
case "$file_path" in
  *".harness/changes/"*"/summary.md") ;;
  *) exit 0 ;;
esac
# 提取卡目录名（.harness/changes/ 与 /summary.md 之间的段）
card_dir="$(printf '%s' "$file_path" | sed -E 's#.*\.harness/changes/([^/]+)/summary\.md$#\1#')"
[ -z "$card_dir" ] && exit 0

# （T-2 · AC-2.6）原此处 `_seg_detect_and_mark` 寄生记号调用已删除；分段建议改由
# user_prompt_state_inject.sh 读盘快照差分承载，门禁判定式与退出码保持不变。

# ---- 翻牌判定（Write 全文覆写 vs Edit 局部片段 · 不对称 · B2）----
flipped=""
if [ "$tool_name" = "Write" ]; then
  content="$(jq -r '.tool_input.content // empty' <<<"$payload" 2>/dev/null || true)"
  [ -n "$content" ] || exit 0
  for ph in 1 3 5; do
    has_phase_passed "$content" "$ph" && flipped="${flipped}${ph} "
  done
elif [ "$tool_name" = "MultiEdit" ]; then
  # MultiEdit（tool_input.edits[] 数组，无顶层 new_string/old_string · code_review_v1 M-1）：
  # 逐子编辑按 Edit 语义判定，任一子编辑翻牌即整体翻牌。edits 解析空/非数组 → fail-open exit 0（AC-10.c）。
  _n_edits="$(jq -r '.tool_input.edits | length // empty' <<<"$payload" 2>/dev/null || true)"
  case "$_n_edits" in
    ''|*[!0-9]*) exit 0 ;;   # 解析不出数量（缺 edits / 非数组 / jq 失败）→ 周边失败 fail-open
  esac
  [ "$_n_edits" -gt 0 ] || exit 0
  _ei=0
  while [ "$_ei" -lt "$_n_edits" ]; do
    new_string="$(jq -r --argjson i "$_ei" '.tool_input.edits[$i].new_string // empty' <<<"$payload" 2>/dev/null || true)"
    old_string="$(jq -r --argjson i "$_ei" '.tool_input.edits[$i].old_string // empty' <<<"$payload" 2>/dev/null || true)"
    _ei=$((_ei + 1))
    [ -n "$new_string" ] || continue
    for ph in 1 3 5; do
      # new 含该阶段 PASSED 且 old 中该阶段原状态非 PASSED → 真翻牌
      if has_phase_passed "$new_string" "$ph"; then
        has_phase_passed "$old_string" "$ph" || case " $flipped " in *" $ph "*) ;; *) flipped="${flipped}${ph} " ;; esac
      fi
    done
  done
else
  # Edit（及其它带 old_string/new_string 的形态）
  new_string="$(jq -r '.tool_input.new_string // empty' <<<"$payload" 2>/dev/null || true)"
  old_string="$(jq -r '.tool_input.old_string // empty' <<<"$payload" 2>/dev/null || true)"
  [ -n "$new_string" ] || exit 0
  for ph in 1 3 5; do
    # new 含该阶段 PASSED 且 old 中该阶段原状态非 PASSED → 真翻牌
    if has_phase_passed "$new_string" "$ph"; then
      has_phase_passed "$old_string" "$ph" || flipped="${flipped}${ph} "
    fi
  done
fi

# 未检测到 1/3/5 翻牌（含翻 N/A、非 1/3/5 行、无 10 阶段表结构的 M 元流程 summary）→ 放行（AC-9）
[ -n "$flipped" ] || exit 0

# ---- 交叉核验 T3 委派台账 ----
# STATE_DIR 根走 harness_state_root() 统一口径（方案甲 · 与写端同源 · feat-segmentation-and-statedir-fix T-B）。
root_dir="$(harness_state_root)"
sdir="${HARNESS_STATE_DIR:-$root_dir/.harness/state}"
session_id="$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null || true)"
sid="$(printf '%s' "${session_id:-nosid}" | tr -cd 'A-Za-z0-9._-')"
[ -n "$sid" ] || sid="nosid"
deleg="$sdir/delegations_${sid}.log"

# 【缺口② 跨-session union · fix-governance-hook-gaps · T2 · UQ-2=a · 冻结契约 ⑦】：sid 中途轮换后 generator
#   委派台账落旧 sid 文件（delegations_<oldsid>.log），T4 翻牌门按新 sid 查询 delegations_<newsid>.log 无记录
#   → 证据类误拦真实委派（同缺口② · 与 pre_bash_guard 授权门同源）。修法 = 委派台账**定位**从「仅当前 sid 文件」
#   放宽为「同 STATE_DIR 内跨全部 delegations_*.log 文件 union」。union 只放松台账**定位**，不放松内容判据——
#   跨卡守恒（$4==card_dir）保留：他卡委派即便命中旧 sid 文件、因 $4!=card_dir 仍 deny（负例守恒）。
# 收集全部可读 delegations_*.log（含当前 sid 与轮换前旧 sid）；`-f && -r` 逐文件过滤（glob 未命中回退字面亦被滤）。
deleg_files=""
for f in "$sdir"/delegations_*.log; do
  [ -f "$f" ] && [ -r "$f" ] && deleg_files="${deleg_files}${f}"$'\n'
done

# AC-10.b 证据类失败：跨全部 sid 文件后仍无任何可读委派台账 → 视同无委派证据 → deny
if [ -z "$deleg_files" ]; then
  printf '[harness:summary_flip_guard] 阻断：产出型阶段（%s）禁止 Owner inline——本会话委派台账缺失或不可读（%s · 跨全部 delegations_*.log 均无可读台账），无 generator 委派证据。请委派 generator 完成后再翻牌（卡 %s）。恢复：确认 PreToolUse(Agent) hook（pretool_agent_delegation_guard.sh）正常落盘委派台账。\n' "$flipped" "$deleg" "$card_dir" >&2
  exit 2
fi

# 同卡 generator 委派记录存在于**任一** sid 文件即放行（首期宽松：阶段号不强制匹配 · $4==card_dir 跨卡守恒）
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if awk -F'\t' -v c="$card_dir" '($2 ~ /generator/) && ($4 == c) {found=1} END{exit found?0:1}' "$f" 2>/dev/null; then
    exit 0
  fi
done <<< "$deleg_files"

# 台账在场但（跨全部 sid 文件）无同卡 generator 记录 → 规则命中 deny（AC-10.a / AC-8）
printf '[harness:summary_flip_guard] 阻断：产出型阶段（%s）禁止 Owner inline，请委派 generator 完成后再翻牌（阶段 %s · 卡 %s）。委派台账中无该卡的 generator 记录——先经 Agent 委派 generator 产出，放行后再翻牌 summary。\n' "$flipped" "$flipped" "$card_dir" >&2
exit 2
