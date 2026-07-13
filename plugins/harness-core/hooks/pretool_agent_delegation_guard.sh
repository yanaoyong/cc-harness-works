#!/usr/bin/env bash
# PreToolUse(Agent|Task) 守卫：委派 generator/reviewer/strategist 时强制校验 prompt 四要素
# （feat-hitl-authz-hardening · T3 · DF-015 · AC-5/6/7/10）。
#
# 契约：
#   * 注册：PreToolUse + matcher="Agent|Task"（本环境委派工具名 = Agent；历史版本 = Task，双兼容）。
#   * 仅对 subagent_type 尾段 ∈ {generator, reviewer, strategist} 生效（含 plugin 前缀如 harness-core:generator）；
#     其余 subagent_type（general-purpose/Explore/Plan/claude…）直接 exit 0 放行（AC-7）。
#   * 四要素（AC-5）：a) tool_input.model 在场；b) prompt 含回合预算字样（「回合预算」/「≤N 回合」）；
#     c) prompt 含产物路径白名单字样（「白名单」/「产物路径」）；d) reviewer/strategist 时 prompt 含「严格约束」。
#     任一缺 → exit 2 + stderr 逐项 ✓/✗ + 缺项补法 + 「补齐后重新发起同一委派」。
#   * 四要素齐全 → exit 0 并追加委派台账 $STATE_DIR/delegations_<sid>.log（供 T4 消费）：
#     <ISO8601>\t<subagent_type>\t<model>\t<目标卡目录>\t<阶段号|unknown>。
#
# AC-10 三层 fail 边界：
#   a) 规则命中（四要素缺项）→ 有意 deny（exit 2）。
#   b) 本 guard 不消费任何台账证据（它写台账、不读），无「证据类失败」场景。
#   c) 周边失败（payload 空/非 JSON、jq 缺失致无法解析 subagent_type/prompt、STATE_DIR 不可写记台账失败、
#      脚本自身错误）→ fail-open exit 0，绝不瘫痪委派链路。
# 禁裸 set -e（AC-10：脚本错误变非 0 退出会误伤委派）——用 set -uo pipefail + 逐命令容错。
set -uo pipefail

# ---- 读取 payload（bash 内建 read；空 stdin/EOF 容错）----
payload=""
IFS= read -r -d '' payload || true
[ -n "$payload" ] || exit 0   # 无 payload → 周边失败 → fail-open（AC-10.c）

# ---- 解析 subagent_type / prompt / model / session_id ----
# jq 缺失 → 无法可靠解析嵌套 JSON（prompt 多行含转义）→ fail-open exit 0（AC-10.c）。
command -v jq >/dev/null 2>&1 || exit 0

subagent_type="$(jq -r '.tool_input.subagent_type // empty' <<<"$payload" 2>/dev/null || true)"
[ -n "$subagent_type" ] || exit 0   # 非委派或解析不出类型 → 放行

# 尾段匹配（剥离 plugin 前缀，如 harness-core:generator → generator）
role="${subagent_type##*:}"
case "$role" in
  generator|reviewer|strategist) ;;
  *) exit 0 ;;   # AC-7：非受控 subagent_type 直接放行
esac

prompt="$(jq -r '.tool_input.prompt // empty' <<<"$payload" 2>/dev/null || true)"
model="$(jq -r '.tool_input.model // empty' <<<"$payload" 2>/dev/null || true)"
session_id="$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null || true)"

# ---- 四要素校验 ----
ok_model=0; [ -n "$model" ] && ok_model=1
ok_budget=0
printf '%s' "$prompt" | grep -qE '回合预算|≤[[:space:]]*[0-9]+[[:space:]]*回合|<=[[:space:]]*[0-9]+[[:space:]]*回合|[0-9]+[[:space:]]*回合' 2>/dev/null && ok_budget=1
ok_whitelist=0
printf '%s' "$prompt" | grep -qE '白名单|产物路径' 2>/dev/null && ok_whitelist=1
# 严格约束仅对 reviewer/strategist 要求；generator 该项恒视为满足
ok_strict=1
if [ "$role" = "reviewer" ] || [ "$role" = "strategist" ]; then
  ok_strict=0
  printf '%s' "$prompt" | grep -qE '严格约束' 2>/dev/null && ok_strict=1
fi

if [ "$ok_model" = "1" ] && [ "$ok_budget" = "1" ] && [ "$ok_whitelist" = "1" ] && [ "$ok_strict" = "1" ]; then
  # ---- 放行 + 写委派台账（AC-6）。写失败 = 纯副作用失败 → 仍放行（AC-10.c）----
  root_dir="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root_dir" ] || root_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  sdir="${HARNESS_STATE_DIR:-$root_dir/.harness/state}"
  sid="$(printf '%s' "${session_id:-nosid}" | tr -cd 'A-Za-z0-9._-')"
  [ -n "$sid" ] || sid="nosid"
  # 目标卡目录：prompt 中首个 .harness/changes/<目录名>
  card_dir="$(printf '%s' "$prompt" | grep -oE '\.harness/changes/[^/[:space:]"'"'"']+' 2>/dev/null | head -1 | sed 's#.*/##')"
  [ -n "$card_dir" ] || card_dir="unknown"
  # 阶段号：prompt 中首个「阶段 N」
  stage="$(printf '%s' "$prompt" | grep -oE '阶段[[:space:]]*[0-9]+' 2>/dev/null | head -1 | grep -oE '[0-9]+' 2>/dev/null | head -1)"
  [ -n "$stage" ] || stage="unknown"
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || true)"
  if [ -n "$ts" ]; then
    mkdir -p "$sdir" 2>/dev/null || true
    [ -f "$sdir/.gitignore" ] || printf '*\n' > "$sdir/.gitignore" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$subagent_type" "$model" "$card_dir" "$stage" \
      >> "$sdir/delegations_${sid}.log" 2>/dev/null || true
  fi
  exit 0
fi

# ---- 阻断 + 逐项 ✓/✗ 修复配方（AC-5）----
mark() { [ "$1" = "1" ] && printf '✓' || printf '✗'; }
{
  printf '[harness:agent_delegation_guard] 阻断：委派 %s 的 prompt 四要素校验未通过（缺项见 ✗）。\n' "$role"
  printf '  [%s] model 参数\n' "$(mark "$ok_model")"
  [ "$ok_model" != "1" ] && printf '      补：委派时显式传 model 参数（按 application-owner.md 模型档默认值表选档）。\n'
  printf '  [%s] 回合预算字样\n' "$(mark "$ok_budget")"
  [ "$ok_budget" != "1" ] && printf '      补：在 prompt 写明回合预算（如「回合预算 ≤40 回合」/「≤15 回合」）。\n'
  printf '  [%s] 产物路径白名单\n' "$(mark "$ok_whitelist")"
  [ "$ok_whitelist" != "1" ] && printf '      补：在 prompt 列出「产物路径白名单」——本次允许写入的文件全限定路径逐一列出。\n'
  if [ "$role" = "reviewer" ] || [ "$role" = "strategist" ]; then
    printf '  [%s] 严格约束段\n' "$(mark "$ok_strict")"
    [ "$ok_strict" != "1" ] && printf '      补：在 prompt 顶部套用 .claude/agents/%s.md 的「严格约束（不可越权）」段。\n' "$role"
  fi
  printf '  补齐后重新发起同一委派。\n'
} >&2
exit 2
