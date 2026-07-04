#!/usr/bin/env bash
# PreToolUse(Skill) 埋点 hook：把每次 skill 调用记一行 JSONL（telemetry / 观测性增强）。
#
# 契约（承接 ADR-005 旁路红线）：
#   * 注册：PreToolUse + matcher="Skill"（与既有 pre_bash_guard.sh 的 matcher="Bash" 平行）。
#   * 纯旁路只读：只把调用事件落盘，绝不拦截/改变 Skill 执行、不修改 tool_input、不写 stdout 干预。
#   * 恒 exit 0：与 pre_bash_guard.sh 的 exit 2 拦截语义【刻意相反】——本 hook 没有任何 exit 2 / 非零路径。
#   * 不进任一阶段门禁判定式、不夺裁决权（与 wiki/codegraph 旁路红线同构）。
#
# JSONL schema（每次调用追加一行 · 落盘 .harness/metrics/skill-usage/events.jsonl · 不入 git）：
#   ts              ISO-8601 本地时间戳（含日期偏移，供日/周/月分桶；date -Iseconds）
#   skill           被调用的 skill 名（来自 tool_input，见下方字段采信说明）
#   agent_role      main / sub / unknown（主 vs 子 Agent，见下方判别说明）
#   session_id      .session_id（透传，供回溯）
#   transcript_path .transcript_path（透传，供回溯）
#   cwd             .cwd（透传，供回溯）
#   tool_name       .tool_name（透传，应为 "Skill"）
#   args            .tool_input.args（截断限长 200 字符 + 疑似密钥键值脱敏后落盘 · AC-9）
#   raw             原始 payload 压成单行存一份（同样过脱敏 · 便于日后回溯重算 role）
#
# skill 字段采信：Skill 工具的入参字段名以官方 hook schema 为准——按 claude-code-guide 查证
#   官方 hooks 文档，Skill 的入参字段为 .tool_input.skill_name；为防 schema 版本差异，采【链式兜底】
#   .tool_input.skill_name // .tool_input.skill // .tool_input.name（`// empty` 兜底）。均空则
#   skill="" 仍落盘（不丢事件）。最终采信字段与依据见 coding_report。
#
# agent_role 判别（AC-7 · 单一正信号，永不伪造）：唯一正信号 = payload .agent_type（兜底 .agent_id）。
#   据 claude-code-guide 查证官方 hooks 文档，PreToolUse 的 stdin JSON 仅在【子 Agent】上下文触发时
#   含 .agent_type / .agent_id 字段（主会话不含）——这是官方唯一保证、可干净区分主/子的信号。
#   (1) payload 可解析（jq 可用且 JSON 合法）：
#         .agent_type 非空（或 .agent_id 非空） → sub  （仅子 Agent 含此字段）
#         否则                                 → main （无子 Agent 标记 = 顶层编排，含后台 Owner，正确）
#   (2) payload 不可解析（空 stdin / 非法 JSON / jq 不可用，读不到 .agent_type）→ unknown，永不伪造。
#   【不采用】CLAUDE_CODE_CHILD_SESSION：它泛指任何非交互/后台/派生会话，后台运行的主 orchestrator
#       （Owner）会话内也 =1，无法干净区分主/子（实测会把后台 Owner 自己的 skill 调用误标 sub）。故移除。
#   判别边界与 unknown 触发条件见 coding_report。
#
# 盲区声明（OQ-4 已决）：本 hook 仅统计【经 Skill 工具发起】的调用；本仓很多阶段 SOP
#   （request-analysis / coding-skill 等 markdown）是把 markdown 当说明书【阅读消费】，不走 Skill 工具，
#   PreToolUse(Skill) 抓不到——此为已声明盲区，不在本卡范围。
#
# 性能（对齐 pre_bash_guard.sh 纪律）：快速路径少子进程、jq ≤1 次、失败即放行；恒 exit 0。
# 健壮性：jq 缺失 / stdin 为空 / 解析失败 → 安全降级（尽力记可得字段，绝不报错、绝不阻断）。
set -euo pipefail

# ---- 读取 payload：bash 内建 read（零子进程；空 stdin / EOF 容错）----
payload=""
IFS= read -r -d '' payload || true

# ---- 日志落点（mkdir -p 失败也不中断；能不记就跳过，但仍 exit 0）----
log_dir="${CLAUDE_PROJECT_DIR:-$PWD}/.harness/metrics/skill-usage"
log_file="$log_dir/events.jsonl"
mkdir -p "$log_dir" 2>/dev/null || exit 0

# ---- 脱敏函数：对疑似密钥/token 的键值打码 + 整体截断限长（AC-9）----
# 纯 bash + sed（≤当前已用子进程预算内），对 key/token/secret/password/credential/authorization
# 等敏感键名后的取值打码为 ***；再硬截断到 max 字符。
redact() {
  local s="$1" max="${2:-200}"
  # 敏感键值打码：匹配 "<senskey>":"<val>" 或 <senskey>=<val> 形态（大小写不敏感）
  # 第二条（LOW-2 修复）：`Bearer <token>` 自由文本 —— authorization 键值规则只打码到
  #   `Bearer` 即停（遇空格停），其后真实 token 仍落盘；此条把 `Bearer<空白><token>` 的
  #   token 整体打码为 ***（覆盖 `Authorization: Bearer xxx` / 裸 `Bearer xxx` 两形态）。
  # sed 表达式按序应用：Bearer 规则【必须先于】authorization 键值规则——否则
  #   `authorization:` 规则会把取值 `Bearer` 自身打码为 `***`，使 Bearer 锚点消失、
  #   其后真实 token 漏排（实测 `Authorization: *** <token>` 残留明文）。先打码 Bearer 后
  #   token，再让 authorization 规则打码 `Bearer` 关键字，两形态（带键名 / 裸 Bearer）均覆盖。
  s="$(printf '%s' "$s" | sed -E \
    -e 's/([Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+)[^",[:space:]]+/\1***/g' \
    -e 's/(("?[Aa][Pp][Ii]_?[Kk][Ee][Yy]"?|"?[Ss][Ee][Cc][Rr][Ee][Tt][A-Za-z_]*"?|"?[Tt][Oo][Kk][Ee][Nn]"?|"?[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]"?|"?[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll][A-Za-z_]*"?|"?[Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]"?)[[:space:]]*[:=][[:space:]]*"?)[^",[:space:]]+/\1***/g' \
    2>/dev/null || printf '%s' "$s")"
  # 硬截断限长
  if [[ "${#s}" -gt "$max" ]]; then
    s="${s:0:max}…"
  fi
  printf '%s' "$s"
}

# ---- 字段提取（jq 存在才用，否则降级；任一提取失败留空字符串，绝不报错）----
ts="$(date -Iseconds 2>/dev/null || true)"
skill=""
session_id=""
transcript_path=""
cwd=""
tool_name=""
args=""
payload_agent_type=""
payload_parsed=0   # 1 = payload 经 jq 成功解析（可读取 .agent_type）；0 = 读不到该字段（空/非法/jq 缺失）
if command -v jq >/dev/null 2>&1 && [[ -n "$payload" ]]; then
  skill="$(jq -r '.tool_input.skill_name // .tool_input.skill // .tool_input.name // empty' <<<"$payload" 2>/dev/null || true)"
  session_id="$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null || true)"
  transcript_path="$(jq -r '.transcript_path // empty' <<<"$payload" 2>/dev/null || true)"
  cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null || true)"
  tool_name="$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null || true)"
  # args：可能是字符串或对象（.tool_input.arguments 文档载为 key-value 对象）——统一 stringify 落盘
  args="$(jq -r '(.tool_input.args // .tool_input.arguments) | if . == null then empty elif type == "string" then . else tojson end' <<<"$payload" 2>/dev/null || true)"
  # payload 侧 role 信号（唯一正信号）：先确认 JSON 合法，再取 .agent_type（兜底 .agent_id）
  if jq -e . >/dev/null 2>&1 <<<"$payload"; then
    payload_parsed=1
    payload_agent_type="$(jq -r '.agent_type // .agent_id // empty' <<<"$payload" 2>/dev/null || true)"
  fi
fi

# ---- agent_role 判别（单一正信号 = payload .agent_type/.agent_id · 永不伪造）----
# payload 不可解析（读不到 .agent_type 字段本身）→ unknown，不硬猜 main/sub。
agent_role="unknown"
if [[ "$payload_parsed" == "1" ]]; then
  if [[ -n "$payload_agent_type" ]]; then
    # 官方保证：仅子 Agent 上下文的 payload 含 .agent_type/.agent_id
    agent_role="sub"
  else
    # payload 解析成功但无子 Agent 标记 = 顶层编排（含后台 Owner 会话，正确标 main）
    agent_role="main"
  fi
fi

# ---- 脱敏 args 与 raw ----
args="$(redact "$args" 200)"
# raw：原始 payload 压成单行（换行→空格）后脱敏，限长 1000 防日志膨胀
raw_oneline="${payload//$'\n'/ }"
raw_oneline="$(redact "$raw_oneline" 1000)"

# ---- 组装一行 JSONL 并追加（jq 在场用 jq 保证合法转义；否则手工转义降级）----
if command -v jq >/dev/null 2>&1; then
  jq -cn \
    --arg ts "$ts" --arg skill "$skill" --arg agent_role "$agent_role" \
    --arg session_id "$session_id" --arg transcript_path "$transcript_path" \
    --arg cwd "$cwd" --arg tool_name "$tool_name" --arg args "$args" \
    --arg raw "$raw_oneline" \
    '{ts:$ts, skill:$skill, agent_role:$agent_role, session_id:$session_id, transcript_path:$transcript_path, cwd:$cwd, tool_name:$tool_name, args:$args, raw:$raw}' \
    >>"$log_file" 2>/dev/null || true
else
  # jq 不可用降级：手工 JSON 转义（\ 与 " 与控制字符），保证仍是合法 JSONL
  esc() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\t'/ }"; s="${s//$'\n'/ }"; s="${s//$'\r'/ }"; printf '%s' "$s"; }
  printf '{"ts":"%s","skill":"%s","agent_role":"%s","session_id":"%s","transcript_path":"%s","cwd":"%s","tool_name":"%s","args":"%s","raw":"%s"}\n' \
    "$(esc "$ts")" "$(esc "$skill")" "$(esc "$agent_role")" "$(esc "$session_id")" \
    "$(esc "$transcript_path")" "$(esc "$cwd")" "$(esc "$tool_name")" "$(esc "$args")" "$(esc "$raw_oneline")" \
    >>"$log_file" 2>/dev/null || true
fi

exit 0
