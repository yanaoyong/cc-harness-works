#!/usr/bin/env bash
# PostToolUse 钩子（旁路观测 · 批量并发回显）：变更卡 feat-batch-echo-and-diet-20260712 · T1。
# 落地 spec §4 T1 组 AC-T1-1~7 + U-2/U-3/U-4/U-5 裁决。
#
# == 目的（装镜子 · 异常才说话）==
# proposal-011/012 实测：主循环批量率仅 1.2–3.4%（互不依赖的读取本可一条消息并发省回合）。
# 纯文字 nudge 会衰减（p010）→ 本 hook 只在**明确异常**时对 Owner（模型）说一句：
# 「最近连续 10 次都是单调用只读工具，若彼此独立可并发」。窗口不满足时**零输出**（非常亮）。
#
# == U-3 机制可行性（本卡阶段 3 起手已验证 · 通过）==
# 单次 PostToolUse 事件无法可靠即时判定「当前这条 assistant 消息是单调用还是批量」——
# 因为一条消息的多个 tool_use 在 transcript 里与其 tool_result **交错写入**（实测：同一
# message.id 的 tool_use 行不保证在结果行之前全部落盘）。故本 hook **不即时分类当前消息**，
# 改为**累积法**：每次 PostToolUse 追加一行 `<message.id>\t<class>` 到会话态计数文件；一条
# 批量消息的 N 个 tool_use → N 行同 message.id（相邻）。判窗口时把「相邻同 id 行」折叠成一条
# 消息：size==1 才算「单调用」，size>1 即批量。message.id 在 PostToolUse 时刻**恒可得**（触发
# 本事件的 tool_use 行必已落盘），故信号可靠。真实批量恒以 size≥2 的相邻同 id 组出现→必破窗、
# 绝不把「高效批量」误报成异常；唯一边界是「批量的第一个工具刚完成、此刻只 1 行貌似单调用」，
# 但要触发提示须其前已累积 ≥9 条真实单调用只读，此情形 nudge 本就正当（U-4 宁可漏计不可误报）。
#
# == U-5 通道选型（实测/权威文档确认）==
# PostToolUse 支持 JSON stdout `hookSpecificOutput.additionalContext`——文档明确「Appears as a
# system reminder on the next model request」，即**注入模型上下文、Owner 可见、且非阻断**
# （exit 0 且无 decision:block → 工具结果照常流转）。stderr(exit0) 只进用户 UI 不进模型上下文；
# systemMessage 同样只进用户 UI。故本 hook 选 additionalContext 作唯一提示通道（Owner=模型可见）。
#
# == U-2 裁决（YAGNI · 写死）==
# 窗口 = 近 10 次、文案固定写死，不做可调参数。
#
# == U-4 裁决（Bash 粗筛只读 · 宁可漏计不可误报）==
# Read/Grep/Glob → 只读；Bash 按命令内容粗筛：命中写类 denylist（git 变更类 / rm/mv/cp/mkdir/
# touch/tee/dd/chmod/chown/ln/truncate/rmdir / 重定向 `>` / `sed -i` / 安装类）→ 记 wr（破窗）；
# v2 修复（阶段4 SHOULD-1 + 阶段5 独立同发现）：①裸 rm / xargs rm 纳入写类；②词元边界类加入
# 引号 "'，使 `bash -c "git push"` / `sh -c 'git commit'` 等引号包裹串命中。过杀（如
# grep "git push" 字面引用被判 wr）可接受——本 hook 是旁路提示非门禁，过杀代价仅为「少提示
# 一次」，与「不可误报假 nudge」取向一致；`grep push file` 等无 git 前缀的字面引用不受影响；
# stage7_push.sh / stage8_ci.sh 脚本化单调用 → 记 ex（豁免·破窗·AC-T1-5：脚本化单调用是设计非坏味道）；
# 其余 → ro。歧义时倾向破窗（漏计只读）以避免误报（错误地打扰 Owner）——旁路提示宁静勿吵。
#
# == 硬约束（AC-T1-6 · 恒 exit 0 · fail-open）==
# jq 缺失 / payload 非 JSON / transcript 不可读 / STATE_DIR 不可写 / 任何解析失败 → 静默 exit 0。
# 本 hook 为旁路观测（ADR-005），无 0.8.1 门类 fail-closed 义务；任何路径永不阻断工具流转。
#
# == 会话态隔离（AC-T1-3）==
# 计数文件 = $STATE_DIR/batch_echo_counter_<sid>.log，STATE_DIR=${HARNESS_STATE_DIR:-$TOP/.harness/state}
# （HARNESS_STATE_DIR 可覆写 · 按项目 + session_id 隔离 · 对齐 statedir v0.6.1 教训）。目录内
# 自落 .gitignore('*') 保证不入库（对齐既有 hook 惯例）。
#
# bash 3.2 兼容（NFR）：无 declare -A / mapfile / readarray / bash4-only 语法；分组折叠用 awk。
set -uo pipefail

PREFIX="[harness:batch_echo]"
WINDOW=10   # U-2 写死

# 写类 denylist（U-4 · 命中即破窗）：git 变更子命令 / 文件系统写（含裸 rm）/ 重定向 / 原地编辑 / 安装类。
# 边界（v2）：命令首词或经 空白 &|;( 及引号 "' 分隔后出现即命中（引号入边界 → bash -c/sh -c
# 包裹串亦命中；xargs rm 经空白边界命中）；重定向 `>`（含 `>>`）出现即命中。
_WRITE_RE="(^|[[:space:]&|;(\"'])(git[[:space:]]+(commit|push|merge|reset|rebase|tag|checkout|branch|add|stash|apply|cherry-pick|am))([[:space:]\"']|\$)|(^|[[:space:]&|;(\"'])(rm|mv|cp|mkdir|touch|tee|dd|chmod|chown|ln|truncate|rmdir|install)([[:space:]\"']|\$)|>|sed[[:space:]]+-i|(npm|pnpm|yarn|pip|pip3)[[:space:]]+(install|add|i)([[:space:]\"']|\$)"
# 脚本化阶段豁免（AC-T1-5 · 命中即破窗·不计只读）
_EXEMPT_RE='stage7_push\.sh|stage8_ci\.sh'

# ---------- 仓库根 / STATE_DIR 定位（三级回退 · 与既有 hook 同口径）----------
_TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$_TOP" ]; then _TOP="${CLAUDE_PROJECT_DIR:-$PWD}"; fi
STATE_DIR="${HARNESS_STATE_DIR:-$_TOP/.harness/state}"

# ---------- 读取 stdin payload（不阻塞）----------
_stdin=""
if [ ! -t 0 ]; then _stdin="$(cat 2>/dev/null || true)"; fi
[ -n "$_stdin" ] || exit 0

# jq 缺失 → fail-open（无法可靠解析 JSON）
command -v jq >/dev/null 2>&1 || exit 0

_tool="$(printf '%s' "$_stdin" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ -n "$_tool" ] || exit 0
_transcript="$(printf '%s' "$_stdin" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
_sid="$(printf '%s' "$_stdin" | jq -r '.session_id // empty' 2>/dev/null || true)"
_cmd="$(printf '%s' "$_stdin" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

# transcript 不可读 → fail-open（拿不到 message.id 就不记录本次，漏计不误报）
[ -n "$_transcript" ] && [ -r "$_transcript" ] || exit 0

# sid 卫生（对齐授权台账写端）
_sid="$(printf '%s' "${_sid:-nosid}" | tr -cd 'A-Za-z0-9._-')"
[ -n "$_sid" ] || _sid="nosid"

# ---------- 取当前 message.id（transcript 尾部最后一条带 tool_use 的 assistant 行）----------
_msgid="$(tail -n 80 "$_transcript" 2>/dev/null \
  | jq -rc 'select(.type=="assistant") | select((.message.content//[])|any(.type=="tool_use")) | .message.id' 2>/dev/null \
  | tail -n 1)"
[ -n "$_msgid" ] || exit 0

# ---------- 分类（U-4）----------
_class="wr"   # 默认破窗（未知工具从保守）
case "$_tool" in
  Read|Grep|Glob) _class="ro" ;;
  Bash)
    if printf '%s' "$_cmd" | grep -qE "$_EXEMPT_RE"; then _class="ex"
    elif printf '%s' "$_cmd" | grep -qE "$_WRITE_RE"; then _class="wr"
    else _class="ro"; fi
    ;;
esac

# ---------- 追加记录（会话态计数文件 · 自落 .gitignore）----------
_cf="$STATE_DIR/batch_echo_counter_${_sid}.log"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
[ -f "$STATE_DIR/.gitignore" ] || printf '*\n' > "$STATE_DIR/.gitignore" 2>/dev/null || true
printf '%s\t%s\n' "$_msgid" "$_class" >> "$_cf" 2>/dev/null || exit 0

# 有界增长：仅保留末 200 行（窗口只需 ≤WINDOW，200 足够含最近若干批量折叠余量）
_lines="$(wc -l < "$_cf" 2>/dev/null || echo 0)"
if [ "${_lines:-0}" -gt 400 ] 2>/dev/null; then
  tail -n 200 "$_cf" > "$_cf.tmp" 2>/dev/null && mv "$_cf.tmp" "$_cf" 2>/dev/null || true
fi

# ---------- 计算「连续单调用只读消息」游程 ----------
# 折叠相邻同 message.id 行为一条消息：size==1 且只读才算「单调用只读」，size>1 即批量→破窗。
# 含当前消息：真实批量恒以 size≥2 组出现→必破窗、绝不误报；唯一边界（批量首个工具尚只 1 行、
# 貌似单）要触发须其前已有 ≥WINDOW−1 条真实单调用只读，此时 nudge 本就正当（U-4 宁可漏计不可误报）。
# awk 输出：`<run>\t<newest_run_msgid>`（newest_run_msgid = 游程内最新一条消息 id · 供 keyfile 去重）
_res="$(awk -F '\t' '
  { mid[NR]=$1; cls[NR]=$2; n=NR }
  END{
    i=n
    run=0; newest=""
    while(i>=1){
      gid=mid[i]; size=0; allro=1; j=i
      while(j>=1 && mid[j]==gid){ if(cls[j]!="ro") allro=0; size++; j-- }
      if(size==1 && allro==1){                    # 单调用只读消息
        if(run==0){ newest=gid }
        run++; i=j
      } else { break }                            # 批量(size>1) / 含非只读 → 破窗
    }
    printf "%s\t%s", run, newest
  }' "$_cf" 2>/dev/null || true)"
_run="${_res%%$'\t'*}"
_newest="${_res#*$'\t'}"
[ -n "$_run" ] || exit 0
case "$_run" in (*[!0-9]*) exit 0 ;; esac        # 非数字 → fail-open

# ---------- 触发（恰在游程 == WINDOW 时·一次·keyfile 去重批量双触发）----------
if [ "$_run" -eq "$WINDOW" ] && [ -n "$_newest" ]; then
  _kf="$STATE_DIR/batch_echo_lastfire_${_sid}"
  _last="$(cat "$_kf" 2>/dev/null || true)"
  if [ "$_last" != "$_newest" ]; then
    printf '%s\n' "$_newest" > "$_kf" 2>/dev/null || true
    _msg="$PREFIX 观测：最近连续 ${WINDOW} 次工具调用均为单调用只读（Read/Grep/Glob/只读Bash）。若这些读取彼此独立，请在一条消息内并发多个工具调用（batch）以省回合——见「子 Agent 委派上下文契约·同阶段并行委派纪律」。"
    jq -nc --arg ctx "$_msg" \
      '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}' 2>/dev/null || true
  fi
fi

exit 0
