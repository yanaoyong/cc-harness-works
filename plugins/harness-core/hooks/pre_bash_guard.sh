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
if [[ "$payload" != *git* && "$payload" != *rm* && "$payload" != *sudo* \
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

exit 0
