#!/usr/bin/env bash
# PreToolUse(Agent|Task) 守卫：委派 generator/reviewer/strategist 时强制校验 prompt 要素
# （feat-hitl-authz-hardening · T3 · DF-015 · AC-5/6/7/10）。
# chore-hook-governance-hardening-20260715 · T-4：generator/reviewer 增「阶段号」第五要素 +
#   读 model_tiers.tsv 对表校验（拦降档漂移 / 放行按风险上调）；strategist 豁免第五要素与对表校验
#   （元流程 M 相位非数字 + model_tiers.tsv 无 M 定义 + R4 元流程边界 · MF-1）。
#
# 契约：
#   * 注册：PreToolUse + matcher="Agent|Task"（本环境委派工具名 = Agent；历史版本 = Task，双兼容）。
#   * 仅对 subagent_type 尾段 ∈ {generator, reviewer, strategist} 生效（含 plugin 前缀如 harness-core:generator）；
#     其余 subagent_type（general-purpose/Explore/Plan/claude…）直接 exit 0 放行（AC-7）。
#   * 四要素（AC-5）：a) tool_input.model 在场；b) prompt 含回合预算字样（「回合预算」/「≤N 回合」）；
#     c) prompt 含产物路径白名单字样（「白名单」/「产物路径」）；d) reviewer/strategist 时 prompt 含「严格约束」。
#   * 第五要素（T-4 · AC-4.1 · 仅 generator/reviewer）：e) prompt 含「阶段 N」字样（阶段[[:space:]]*[0-9]+）；
#     strategist 豁免本要素（无「阶段 N」不 deny）。
#     任一缺（四/五要素）→ exit 2 + stderr 逐项 ✓/✗ + 缺项补法 + 「补齐后重新发起同一委派」。
#   * 要素齐全后对表校验（T-4 · AC-4.2/4.3/4.4 · 仅 generator/reviewer）：读 model_tiers.tsv 取该阶段默认档，
#     委派 model 归一化后档位（序 haiku<sonnet<opus）低于默认档 → exit 2（降档漂移 deny）；等于/高于 → 放行（上调不拦）。
#   * 校验通过 → exit 0 并追加委派台账 $STATE_DIR/delegations_<sid>.log（供 T4 消费）：
#     <ISO8601>\t<subagent_type>\t<model>\t<目标卡目录>\t<阶段号|unknown>。
#
# AC-10 三层 fail 边界：
#   a) 规则命中（四/五要素缺项、对表降档）→ 有意 deny（exit 2）。
#   b) 本 guard 不消费任何台账证据（它写台账、不读），无「证据类失败」场景。
#   c) 周边失败（payload 空/非 JSON、jq 缺失致无法解析 subagent_type/prompt、STATE_DIR 不可写记台账失败、
#      脚本自身错误）→ fail-open exit 0，绝不瘫痪委派链路。
#   c') 对表周边失败（T-4 · AC-4.4）：阶段号不在表（如阶段 10）/ 档位表缺失不可读解析失败 / model 归一后
#      不在 {haiku,sonnet,opus} 可比档（如 fable）→ fail-open 放行。理由 = 档位表是「配置」非「证据」
#      （缺表 = 不知该拦什么，宁放行不误伤合法委派），与 T4 翻牌门证据类 fail-closed 有意非对称（UQ-3）。
# 禁裸 set -e（AC-10：脚本错误变非 0 退出会误伤委派）——用 set -uo pipefail + 逐命令容错。
set -uo pipefail

# harness_state_root —— STATE_DIR 根解析单一口径（方案甲 · 锚 CLAUDE_PROJECT_DIR · 内联兜底逐字同
# lib/shell-utils.sh · feat-segmentation-and-statedir-fix-20260714 T-B）。会话中途 cwd 漂移下稳定。
# 本 hook 原写端口径已锚 CLAUDE_PROJECT_DIR（族 B · 正确），此处仅归一到单一命名口径、行为零回归。
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

# tier_rank —— 档位序 haiku<sonnet<opus 映射为可比整数（0=不可比/未知）；纯 bash · 无子进程
# chore-hook-governance-hardening-20260715 · T-4 · AC-4.2/4.4。结果写全局 TIER_RANK（免 $() 子壳）。
tier_rank() {
  case "$1" in
    haiku)  TIER_RANK=1 ;;
    sonnet) TIER_RANK=2 ;;
    opus)   TIER_RANK=3 ;;
    *)      TIER_RANK=0 ;;
  esac
}

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

# 阶段号解析（复用既有正则 · 供第五要素校验 / 对表校验 / 台账三处共用 · T-4）
# chore-hook-governance-hardening-20260715 · T-4：由原放行块内解析上移，净零子进程增量。
stage="$(printf '%s' "$prompt" | grep -oE '阶段[[:space:]]*[0-9]+' 2>/dev/null | head -1 | grep -oE '[0-9]+' 2>/dev/null | head -1)"

# ---- 要素校验（四要素 + generator/reviewer 第五要素）----
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
# 第五要素：阶段号必填（仅 generator/reviewer · T-4 · AC-4.1）；strategist 豁免（M 相位非数字 · MF-1）→ 恒视为满足
ok_stage=1
if [ "$role" = "generator" ] || [ "$role" = "reviewer" ]; then
  ok_stage=0
  [ -n "$stage" ] && ok_stage=1
fi

if [ "$ok_model" = "1" ] && [ "$ok_budget" = "1" ] && [ "$ok_whitelist" = "1" ] && [ "$ok_strict" = "1" ] && [ "$ok_stage" = "1" ]; then
  # STATE_DIR 根走 harness_state_root() 统一口径（方案甲 · T-B）
  root_dir="$(harness_state_root)"

  # ---- 对表校验（仅 generator/reviewer · T-4 · AC-4.2/4.3/4.4）----
  # chore-hook-governance-hardening-20260715 · T-4：读 model_tiers.tsv 对该阶段默认档做降档校验。
  # strategist 豁免（model_tiers.tsv 只覆盖阶段 1-9、对 M 相位无定义 · MF-1）。
  if [ "$role" = "generator" ] || [ "$role" = "reviewer" ]; then
    # model 归一化：trim 首尾空白 + lowercase（纯 bash · 无子进程 · SG-1/AC-4.4）
    model_norm="${model#"${model%%[![:space:]]*}"}"
    model_norm="${model_norm%"${model_norm##*[![:space:]]}"}"
    model_norm="${model_norm,,}"
    tier_rank "$model_norm"; mrank="$TIER_RANK"
    # 定位档位表：仓根 plugins 源 → .harness 镜像（消费方安装态回退）；两处均无 → tsv 空 → fail-open
    tsv=""
    for cand in "$root_dir/plugins/harness-core/config/model_tiers.tsv" "$root_dir/.harness/config/model_tiers.tsv"; do
      [ -r "$cand" ] && { tsv="$cand"; break; }
    done
    default_tier=""
    if [ -n "$tsv" ]; then
      # awk 解析：跳过 # 注释行，取阶段号匹配行第 2 列（唯一新增 awk 子进程 · 编码约束 awk ≤1）
      default_tier="$(awk -F'\t' -v s="$stage" '/^[[:space:]]*#/ {next} $1==s {print $2; exit}' "$tsv" 2>/dev/null || true)"
    fi
    # default_tier 归一化（纯 bash · 防表值含 CR/空白）
    default_tier="${default_tier#"${default_tier%%[![:space:]]*}"}"
    default_tier="${default_tier%"${default_tier##*[![:space:]]}"}"
    default_tier="${default_tier,,}"
    tier_rank "$default_tier"; drank="$TIER_RANK"
    # deny 仅当：model 可比(mrank≠0) ∧ 默认档可比(drank≠0) ∧ model 严格低于默认档。
    # 其余（阶段不在表 → drank=0 / 表缺失 → drank=0 / model 不可比如 fable → mrank=0）→ fail-open 放行（AC-4.4/UQ-3）。
    if [ "$mrank" != "0" ] && [ "$drank" != "0" ] && [ "$mrank" -lt "$drank" ]; then
      {
        printf '[harness:agent_delegation_guard] 阻断：委派 %s 存在模型降档漂移（对表校验未通过）。\n' "$role"
        printf '  阶段 %s 默认档 = %s，当前传 %s 属降档漂移（档位序 haiku<sonnet<opus）。\n' "$stage" "$default_tier" "$model_norm"
        printf '      补：把 model 上调至 ≥ %s（Owner 可按风险上调、但禁降档）；若阶段号有误请修正阶段号。\n' "$default_tier"
        printf '  补齐后重新发起同一委派。\n'
      } >&2
      exit 2
    fi
  fi

  # ---- 放行 + 写委派台账（AC-6）。写失败 = 纯副作用失败 → 仍放行（AC-10.c）----
  sdir="${HARNESS_STATE_DIR:-$root_dir/.harness/state}"
  sid="$(printf '%s' "${session_id:-nosid}" | tr -cd 'A-Za-z0-9._-')"
  [ -n "$sid" ] || sid="nosid"
  # 目标卡目录：prompt 中首个 .harness/changes/<目录名>
  card_dir="$(printf '%s' "$prompt" | grep -oE '\.harness/changes/[^/[:space:]"'"'"']+' 2>/dev/null | head -1 | sed 's#.*/##')"
  [ -n "$card_dir" ] || card_dir="unknown"
  # 台账第五列阶段号（AC-4.5）：generator/reviewer 已过第五要素校验必有值；strategist 尽力解析（缺则 unknown）。
  stage_col="$stage"
  [ -n "$stage_col" ] || stage_col="unknown"
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || true)"
  if [ -n "$ts" ]; then
    mkdir -p "$sdir" 2>/dev/null || true
    [ -f "$sdir/.gitignore" ] || printf '*\n' > "$sdir/.gitignore" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$subagent_type" "$model" "$card_dir" "$stage_col" \
      >> "$sdir/delegations_${sid}.log" 2>/dev/null || true
  fi
  exit 0
fi

# ---- 阻断 + 逐项 ✓/✗ 修复配方（AC-5）----
mark() { [ "$1" = "1" ] && printf '✓' || printf '✗'; }
{
  printf '[harness:agent_delegation_guard] 阻断：委派 %s 的 prompt 要素校验未通过（缺项见 ✗）。\n' "$role"
  printf '  [%s] model 参数\n' "$(mark "$ok_model")"
  [ "$ok_model" != "1" ] && printf '      补：委派时显式传 model 参数（按 application-owner.md 模型档默认值表选档）。\n'
  printf '  [%s] 回合预算字样\n' "$(mark "$ok_budget")"
  [ "$ok_budget" != "1" ] && printf '      补：在 prompt 写明回合预算（如「回合预算 ≤40 回合」/「≤15 回合」）。\n'
  printf '  [%s] 产物路径白名单\n' "$(mark "$ok_whitelist")"
  [ "$ok_whitelist" != "1" ] && printf '      补：在 prompt 列出「产物路径白名单」——本次允许写入的文件全限定路径逐一列出。\n'
  if [ "$role" = "generator" ] || [ "$role" = "reviewer" ]; then
    printf '  [%s] 阶段号（第五要素 · 阶段 N 字样）\n' "$(mark "$ok_stage")"
    [ "$ok_stage" != "1" ] && printf '      补：在 prompt 写明本任务阶段号（如「阶段 3」）。\n'
  fi
  if [ "$role" = "reviewer" ] || [ "$role" = "strategist" ]; then
    printf '  [%s] 严格约束段\n' "$(mark "$ok_strict")"
    [ "$ok_strict" != "1" ] && printf '      补：在 prompt 顶部套用 .claude/agents/%s.md 的「严格约束（不可越权）」段。\n' "$role"
  fi
  printf '  补齐后重新发起同一委派。\n'
} >&2
exit 2
