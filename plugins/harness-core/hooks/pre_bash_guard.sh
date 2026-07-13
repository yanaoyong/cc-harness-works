#!/usr/bin/env bash
# PreToolUse(Bash) 守卫：危险命令拦截（既有）+ 直推 main 拦截（DF-007/DF-008）+ 跨分支复合命令拦截（DF-011 第②条）
# 输入：stdin 为 Claude Code 的工具调用 JSON（含 tool_input.command）
# 契约：exit 2 = 阻断并把 stderr 反馈给模型；exit 0 = 放行（stdout/stderr 不反馈模型，故放行路径不输出）
# 旁路（HITL-1 Q2 决议 + HITL-3 LOW#2 方案 A）：仅命令前缀 HARNESS_GIT_GUARD_BYPASS=1 → 放行；审计痕迹 = 前缀本身
#   （hook 进程环境变量形态已删除——持久 export 会静默整体关闭守卫且无逐命令留痕，违背 Q2 审计口径）
# 定位（spec R2）：纪律性护栏而非安全沙箱——不承诺对抗性绕过防护（如 `git -C <path> push origin main` 为已知接受漏拦）
# 性能（NFR-P / AC-7）：快速路径零外部子进程；重路径子进程预算 ≤2（jq ≤1 + 仅 A-2 场景 git ≤1）；全部匹配用 bash 内建 [[ =~ ]]，无外部 grep
set -euo pipefail

# ---- 读取 payload：bash 内建 read（零子进程；空 stdin / EOF 容错）----
payload=""
IFS= read -r -d '' payload || true

# ---- 快速路径（AC-7①）：payload 不含 git 且不含危险模式粗筛关键词 → 纯内建判断，立即放行 ----
# 注：`gh` 关键词纳入粗筛（feat-hitl-authz-hardening T2）——`gh pr merge` 不含 `git` 子串，
# 若不纳入会被此处提前放行、绕过下方 merge 授权硬门。
if [[ "$payload" != *git* && "$payload" != *gh* && "$payload" != *rm* && "$payload" != *sudo* \
   && "$payload" != *mkfs* && "$payload" != *chmod* && "$payload" != *':()'* \
   && "$payload" != */dev/sd* ]]; then
  exit 0
fi

# ---- 重路径：提取 tool_input.command（jq ≤1 次子进程；jq 缺失/解析失败/提取为空 → 降级对 payload 原文匹配，宁漏勿误拦）----
cmd=""
if command -v jq >/dev/null 2>&1; then
  cmd="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null || true)"
fi
if [[ -z "$cmd" ]]; then
  cmd="$payload"
fi

# ---- 旁路：命令前缀形态（Q2 决议 · HITL-3 方案 A 后唯一形态，命中即放行、不输出）----
# 判定用临时变量去前导空白（bash 内建，零子进程），不改写 cmd 本体、不影响下游规则匹配。
cmd_lstrip="${cmd#"${cmd%%[![:space:]]*}"}"
if [[ "$cmd_lstrip" == 'HARNESS_GIT_GUARD_BYPASS=1 '* ]]; then
  exit 0
fi

# ---- 危险命令模式（既有逐条原样保留；--force 以子串从严命中 --force-with-lease；含 { 的模式先存变量再 =~）----
re_dangerous='rm[[:space:]]+-rf|rm[[:space:]]+-fr|[[:space:]]sudo[[:space:]]|mkfs|:\(\)\{|>[[:space:]]*/dev/sd|chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/|git[[:space:]]+push[[:space:]]+.*--force'
if [[ "$cmd" =~ $re_dangerous ]]; then
  echo "[harness:pre_bash_guard] 阻断：检测到不可逆/危险命令（违反 DF-007）。如确需执行，请人工确认。" >&2
  exit 2
fi

# ---- 规则 B：跨分支复合命令拦截（DF-011 第②条机械化）----
# 先于规则 A 判定，保证 B 类反例（如 git switch main && git push origin main）归因 DF-011。
# 双条件：跨分支动作（checkout/switch/merge/branch -d|-D 命令 token）+ 另一分段中的 git 写操作；
# 分隔符 &&/;/||（Q1 决议 (b)），单管道 | 不视作串联；token 匹配带前界，不误拦 commit message 关键词字样 / gh pr merge。
re_b_cross='(^|[[:space:]])git[[:space:]]+(checkout|switch|merge)([[:space:]]|$)|(^|[[:space:]])git[[:space:]]+branch[[:space:]]+-[dD]([[:space:]]|$)'
re_b_write='(^|[[:space:]])git[[:space:]]+(commit|push|merge|checkout|switch|rebase|reset|cherry-pick)([[:space:]]|$)|(^|[[:space:]])git[[:space:]]+branch[[:space:]]+-[dD]([[:space:]]|$)'
if [[ "$cmd" == *'&&'* || "$cmd" == *';'* || "$cmd" == *'||'* ]]; then
  seglist="${cmd//&&/$'\n'}"
  seglist="${seglist//\|\|/$'\n'}"
  seglist="${seglist//;/$'\n'}"
  cross_seen=0
  write_seen=0
  while IFS= read -r seg; do
    is_cross=0
    is_write=0
    if [[ "$seg" =~ $re_b_cross ]]; then is_cross=1; fi
    if [[ "$seg" =~ $re_b_write ]]; then is_write=1; fi
    if [[ ( "$is_cross" == "1" && "$write_seen" == "1" ) || ( "$is_write" == "1" && "$cross_seen" == "1" ) ]]; then
      echo "[harness:pre_bash_guard] 阻断：复合 git 命令串联跨分支动作（违反 DF-011 第②条）。改正：分步执行，每步先以 git branch --show-current 核对当前分支后再继续下一步。" >&2
      exit 2
    fi
    if [[ "$is_cross" == "1" ]]; then cross_seen=1; fi
    if [[ "$is_write" == "1" ]]; then write_seen=1; fi
  done <<< "$seglist"
fi

# ---- 规则 A-1：显式 refspec 指向 main（DF-007/DF-008 机械化）----
# ERE 无 \b：main 词边界用排除字符类 + 行尾实现；尾界排除 :（main:other 目标非 main，放行）与 - / . （maintenance/main-fix/main.x 不误拦）；
# [^;&|]* 限定在单一分段内匹配，避免跨分隔符误命中。
re_a1='(^|[[:space:]])git[[:space:]]+push[[:space:]]+[^;&|]*[[:space:]:]main([^[:alnum:]_/:.-]|$)'
if [[ "$cmd" =~ $re_a1 ]]; then
  echo "[harness:pre_bash_guard] 阻断：直推 main（违反 DF-007/DF-008）。改正：在变更分支 change/<type>-<slug>-<YYYYMMDD> 上 push 并开 PR，经显式授权后以 merge commit 合并进 main。" >&2
  exit 2
fi

# ---- 规则 A-2：裸 push / 不含冒号的 HEAD refspec，且当前分支为 main ----
# 形态：git push [选项/origin/HEAD]*（无显式 refspec 目标）；仅此场景调用 git（≤1 次，AC-7②）；
# 分支判定以 CLAUDE_PROJECT_DIR 锚定，失败（非 git 仓/git 不可用）安全降级放行（AC-5，宁漏勿误拦）。
re_a2='(^|[[:space:]])git[[:space:]]+push([[:space:]]+(-[^[:space:];&|]+|origin|HEAD))*[[:space:]]*($|[;&|])'
if [[ "$cmd" =~ $re_a2 ]]; then
  branch="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" branch --show-current 2>/dev/null || true)"
  if [[ "$branch" == "main" ]]; then
    echo "[harness:pre_bash_guard] 阻断：当前分支为 main，裸 git push（或 HEAD refspec）等价直推 main（违反 DF-007/DF-008）。改正：切到变更分支后再 push 并开 PR，经显式授权后合并进 main。" >&2
    exit 2
  fi
fi

# ---- 规则 T2：merge/push 用户授权硬门（feat-hitl-authz-hardening · DF-015 · AC-2/3/4/10）----
# 凭 T1 用户授权台账（user_prompt_state_inject.sh 落盘 · 仅真实用户输入触发）判定放行。
# 授权窗口 = 并集：条目属最近 5 条用户输入 **或** 时间戳 60 分钟内；内容须同时命中 approve 组 + gate 组。
# 消费 = 追加 CONSUMED 记录行（append-only，不改写原条目）；同 gate 已消费条目不可复用；merge/push 两 gate 独立。
# AC-10 三层：规则命中/台账缺失不可读不可解析（证据类）→ deny；纯副作用（写 CONSUMED）失败 → fail-open 放行。
# 本段刻意 set +e（AC-10：禁裸 set -e 让脚本错误变非 0 退出误伤）——周边失败显式 fail-open、证据失败显式 deny。
set +e
# T2 命令识别（feat-hitl-authz-hardening v5 · 全局参数绕过闭合 · AC-2/3/4/10）：
# 修前要求 `git push` / `gh pr merge` 词元相邻，git/gh 的全局参数插入即失配 → 授权门被绕过。
# 修后容忍 git/gh 与子命令之间夹全局参数序列，并容忍绝对路径调用与 env 前缀：
#   git 全局参数：-C <arg> / -c <arg> / --git-dir[=| ]<arg> / --work-tree[=| ]<arg> / --namespace <arg>
#                 / --exec-path / --config-env / --super-prefix，及任意 flag-only 短/长选项（-x / --xxx）；
#   gh  全局参数：-R/--repo[=| ]<arg> / --hostname[=| ]<arg>，及任意 flag-only 短/长选项；
#   前缀边界 `(^|[[:space:]]|/)`：容忍 `/usr/bin/git`（路径前缀，/ 紧邻 git）；env 前缀（`env A=B git`）本就落在空格边界。
# 取向声明（HITL-authz v5）：**过匹配 = fail-closed 方向可接受，欠匹配不可接受**——故子命令须为 push / pr merge
#   （options 消费后首个非选项 token），既不放过全局参数绕过，`git -C <p> status` 之类非 push 子命令仍归 none。
# bash -c / sh -c 字符串包裹：引号使内层 git/gh 的前缀边界失配（如 `"git push`），故按保守方向兜底——
#   命令含 `bash -c`/`sh -c` 且载荷含 push / `pr merge` 词元即按对应门处理（fail-closed 过匹配，不漏）。
#   反例区分：`echo "git push 教程"` 无 bash/sh -c 包裹、且引号边界失配 → 归 none 放行（非误伤）。
_authz_gate=""
_gitopt='(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir([[:space:]]+|=)[^[:space:]]+|--work-tree([[:space:]]+|=)[^[:space:]]+|--namespace[[:space:]]+[^[:space:]]+|--exec-path([[:space:]]+|=)[^[:space:]]+|--config-env[[:space:]]+[^[:space:]]+|--super-prefix[[:space:]]+[^[:space:]]+|-[[:alpha:]]|--[[:alnum:]-]+)'
_ghopt='(-R[[:space:]]+[^[:space:]]+|--repo([[:space:]]+|=)[^[:space:]]+|--hostname([[:space:]]+|=)[^[:space:]]+|-[[:alpha:]]|--[[:alnum:]-]+)'
_re_merge="(^|[[:space:]]|/)gh([[:space:]]+$_ghopt)*[[:space:]]+pr([[:space:]]+$_ghopt)*[[:space:]]+merge([[:space:]]|$)"
_re_push="(^|[[:space:]]|/)git([[:space:]]+$_gitopt)*[[:space:]]+push([[:space:]]|$)"
if [[ "$cmd" =~ $_re_merge ]]; then
  _authz_gate="merge"
elif [[ "$cmd" =~ $_re_push ]]; then
  _authz_gate="push"
elif { [[ "$cmd" == *'bash -c'* ]] || [[ "$cmd" == *'sh -c'* ]]; } && [[ "$cmd" == *push* ]]; then
  _authz_gate="push"
elif { [[ "$cmd" == *'bash -c'* ]] || [[ "$cmd" == *'sh -c'* ]]; } && [[ "$cmd" =~ pr[[:space:]]+merge ]]; then
  _authz_gate="merge"
fi

if [[ -n "$_authz_gate" ]]; then
  # 词表（UQ-2：内置硬编码 + 环境变量覆写；未设/空/解析失败 → 内置兜底；逗号亦作分隔符归一为 |）
  _aw_approve="${HARNESS_AUTHZ_WORDS_APPROVE:-}"; _aw_approve="${_aw_approve//,/|}"
  [[ -z "$_aw_approve" ]] && _aw_approve='授权|同意|approve'
  if [[ "$_authz_gate" == "merge" ]]; then
    _aw_action="${HARNESS_AUTHZ_WORDS_MERGE:-}"; _aw_action="${_aw_action//,/|}"
    [[ -z "$_aw_action" ]] && _aw_action='合并|merge'
  else
    _aw_action="${HARNESS_AUTHZ_WORDS_PUSH:-}"; _aw_action="${_aw_action//,/|}"
    [[ -z "$_aw_action" ]] && _aw_action='推送|push|PR'
  fi

  # 台账定位（与 T1 写端同口径：STATE_DIR + session_id）
  _root_dir="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -z "$_root_dir" ]] && _root_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  _sdir="${HARNESS_STATE_DIR:-$_root_dir/.harness/state}"
  _sid=""
  if command -v jq >/dev/null 2>&1; then
    _sid="$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null || true)"
  fi
  if [[ -z "$_sid" ]]; then
    _sid="$(printf '%s' "$payload" | tr -d '\n\r' \
      | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 \
      | sed -E 's/.*"session_id"[[:space:]]*:[[:space:]]*"//; s/"$//')"
  fi
  _sid="$(printf '%s' "${_sid:-nosid}" | tr -cd 'A-Za-z0-9._-')"
  [[ -z "$_sid" ]] && _sid="nosid"
  _ledger="$_sdir/user_prompts_${_sid}.log"

  # 本轮 prompt_id（code_review_v1 S-1 · CONSUMED 幂等键）：双注册点同时生效时同一 Bash 调用触发两次，
  # 两次共享同一 prompt_id。CONSUMED 追加 prompt_id 字段；判定时若本 gate 已有同 prompt_id 的 CONSUMED
  # 记录 → 视为本轮已授权放行（幂等重入 · 不二次消费、不误拒）；不同 prompt_id 才算真消费冲突。
  # 空 prompt_id（字段缺失）→ 不启用幂等短路（避免跨轮空==空误放行），退化为既有单次消费语义。
  _prompt_id=""
  if command -v jq >/dev/null 2>&1; then
    _prompt_id="$(jq -r '.prompt_id // empty' <<<"$payload" 2>/dev/null || true)"
  fi
  if [[ -z "$_prompt_id" ]]; then
    _prompt_id="$(printf '%s' "$payload" | tr -d '\n\r' \
      | grep -o '"prompt_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 \
      | sed -E 's/.*"prompt_id"[[:space:]]*:[[:space:]]*"//; s/"$//')"
  fi
  _prompt_id="$(printf '%s' "${_prompt_id}" | tr -cd 'A-Za-z0-9._-')"

  # AC-10.b 证据类失败：台账缺失/不可读/非普通文件（结构性不可解析）→ 视同无证据 → fail-closed。
  # `-f` 前置校验（不止 `-r`）：目录/设备/管道等占位路径对 `-r` 恒真、但后续 while-read 会崩，
  # 故须显式要求"存在→普通可读文件，否则 deny"（feat-hitl-authz-hardening v2 · unit_test 发现②）。
  if [[ ! -f "$_ledger" || ! -r "$_ledger" ]]; then
    if [[ "$_authz_gate" == "merge" ]]; then _hint='授权/同意/approve + 合并/merge'; else _hint='授权/同意/approve + 推送/push/PR'; fi
    echo "[harness:pre_bash_guard] 阻断（授权硬门·${_authz_gate}）：本会话用户授权台账缺失/不可读/非普通文件（台账异常：$_ledger）。证据类失败按 fail-closed 拒绝（避免删/坏台账绕过授权门）。恢复：确认 UserPromptSubmit hook（user_prompt_state_inject.sh）正常落盘后，请用户显式输入含「${_hint}」的授权语再重试。" >&2
    exit 2
  fi

  _now_epoch="$(date +%s 2>/dev/null || echo 0)"
  # 命令携带的 PR 号（# 号或 pr merge N）
  _cmd_pr="$(printf '%s' "$cmd" | grep -oE '#[0-9]+|merge[[:space:]]+[0-9]+|pr[[:space:]]+[0-9]+' 2>/dev/null | head -1 | grep -oE '[0-9]+' 2>/dev/null | head -1)"

  # 收集 prompt 条目（排除 CONSUMED 记录行）、本 gate 已消费时间戳、本 gate 已消费 prompt_id 集
  _entries=()
  _consumed=""
  _consumed_pids=""
  # 防御第二层（发现②）：显式初始化 _ln，杜绝 set -u 下 read 从未赋值（如台账异常/首轮读失败）时
  # `[[ -n "$_ln" ]]` 触发 "unbound variable" 致 exit 1（非受控退出码）。与上方 -f 前置校验双保险。
  _ln=""
  while IFS= read -r _ln || [[ -n "$_ln" ]]; do
    [[ -z "$_ln" ]] && continue
    if [[ "$_ln" == "CONSUMED "* ]]; then
      # CONSUMED <gate> <now-ts> <被消费条目 ts> [<prompt_id>]（prompt_id 为 S-1 新增末字段·旧记录无该字段兼容）
      if [[ "$_ln" == "CONSUMED $_authz_gate "* ]]; then
        _ets_c="$(printf '%s' "$_ln" | awk '{print $4}')"
        [[ -n "$_ets_c" ]] && _consumed="${_consumed}|${_ets_c}|"
        _pid_c="$(printf '%s' "$_ln" | awk '{print $5}')"
        [[ -n "$_pid_c" ]] && _consumed_pids="${_consumed_pids}|${_pid_c}|"
      fi
      continue
    fi
    _entries+=("$_ln")
  done < "$_ledger"

  # S-1 幂等短路：本 gate 已有同 prompt_id 的 CONSUMED → 本轮已授权，放行（双注册双触发的第二次不误拒、不重复消费）。
  # 仅当 _prompt_id 非空时启用（空 prompt_id 退化为既有单次消费语义，杜绝跨轮空==空误放行）。
  if [[ -n "$_prompt_id" ]]; then
    case "$_consumed_pids" in
      *"|$_prompt_id|"*) exit 0 ;;
    esac
  fi

  _n=${#_entries[@]}
  _matched_ts=""
  _i=$_n
  while [[ $_i -gt 0 ]]; do
    _i=$((_i - 1))
    _entry="${_entries[$_i]}"
    _rank=$(( _n - _i ))   # 1 = 最新
    _ets="$(printf '%s' "$_entry" | awk -F'\t' '{print $1}')"
    _etext="${_entry#*$'\t'}"
    # 窗口并集：最近 5 条 OR 60 分钟内（时间解析失败则仅凭条数窗口，优雅降级）
    _ok_win=0
    [[ $_rank -le 5 ]] && _ok_win=1
    if [[ $_ok_win -eq 0 && "$_now_epoch" != "0" && -n "$_ets" ]]; then
      _eep="$(date -d "$_ets" +%s 2>/dev/null || true)"
      if [[ -n "$_eep" ]]; then
        _age=$(( _now_epoch - _eep ))
        [[ $_age -ge 0 && $_age -le 3600 ]] && _ok_win=1
      fi
    fi
    [[ $_ok_win -eq 0 ]] && continue
    # 内容：approve 组 AND gate 组
    printf '%s' "$_etext" | grep -qE "$_aw_approve" 2>/dev/null || continue
    printf '%s' "$_etext" | grep -qE "$_aw_action" 2>/dev/null || continue
    # PR 号一致性：命令含号且授权条目含号则须一致
    if [[ -n "$_cmd_pr" ]]; then
      _entry_pr="$(printf '%s' "$_etext" | grep -oE '#[0-9]+' 2>/dev/null | head -1 | grep -oE '[0-9]+' 2>/dev/null | head -1)"
      [[ -n "$_entry_pr" && "$_entry_pr" != "$_cmd_pr" ]] && continue
    fi
    # 未被本 gate 消费
    case "$_consumed" in
      *"|$_ets|"*) continue ;;
    esac
    _matched_ts="$_ets"
    break
  done

  if [[ -n "$_matched_ts" ]]; then
    # 消费：追加 CONSUMED 记录（append-only）。写失败 = 纯副作用失败 → fail-open 放行（AC-10.c）。
    # 末字段 prompt_id（S-1）供双注册双触发的幂等重入识别；缺失时写 `-` 占位（保持字段数稳定）。
    _cts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || true)"
    printf 'CONSUMED %s %s %s %s\n' "$_authz_gate" "${_cts:-unknown}" "$_matched_ts" "${_prompt_id:--}" >> "$_ledger" 2>/dev/null || true
    exit 0
  fi

  # 台账在场但无未消费的匹配授权 → 规则命中 fail-closed（AC-10.a）
  if [[ "$_authz_gate" == "merge" ]]; then _hint='授权/同意/approve 与 合并/merge'; else _hint='授权/同意/approve 与 推送/push/PR'; fi
  [[ -n "$_cmd_pr" ]] && _hint="${_hint}，且 PR 号 #${_cmd_pr} 一致"
  echo "[harness:pre_bash_guard] 阻断（授权硬门·${_authz_gate}）：本会话台账近期（最近 5 条或 60 分钟内）无未消费的用户授权痕迹。改正：请用户显式输入授权语（须同时含 ${_hint}）后重试；单条授权对同一 gate 仅可消费一次。" >&2
  exit 2
fi

exit 0
