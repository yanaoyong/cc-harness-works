#!/usr/bin/env bash
# PreToolUse(Bash) 守卫：危险命令拦截（既有）+ 直推 main 拦截（DF-007/DF-008）+ 跨分支复合命令拦截（DF-011 第②条）
# 输入：stdin 为 Claude Code 的工具调用 JSON（含 tool_input.command）
# 契约：exit 2 = 阻断并把 stderr 反馈给模型；exit 0 = 放行（stdout/stderr 不反馈模型，故放行路径不输出）
# 旁路（HITL-1 Q2 决议 + HITL-3 LOW#2 方案 A）：仅命令前缀 HARNESS_GIT_GUARD_BYPASS=1 → 放行；审计痕迹 = 前缀本身
#   （hook 进程环境变量形态已删除——持久 export 会静默整体关闭守卫且无逐命令留痕，违背 Q2 审计口径）
# 定位（spec R2）：纪律性护栏而非安全沙箱——不承诺对抗性绕过防护（如 `git -C <path> push origin main` 为已知接受漏拦）
# 性能（NFR-P / AC-7）：快速路径零外部子进程；重路径子进程预算 ≤2（jq ≤1 + 仅 A-2 场景 git ≤1）；全部匹配用 bash 内建 [[ =~ ]]，无外部 grep
set -euo pipefail

# harness_state_root —— STATE_DIR 根解析单一口径（方案甲 · 锚 CLAUDE_PROJECT_DIR · 内联兜底逐字同
# lib/shell-utils.sh · feat-segmentation-and-statedir-fix-20260714 T-B）。会话中途 cwd 漂移下稳定。
# 本 hook 原读端口径已锚 CLAUDE_PROJECT_DIR（族 B · 正确），此处仅归一到单一命名口径、行为零回归。
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

# ---- 读取 payload：bash 内建 read（零子进程；空 stdin / EOF 容错）----
payload=""
IFS= read -r -d '' payload || true

# ---- 快速路径（AC-7①）：payload 不含 git 且不含危险模式粗筛关键词 → 纯内建判断，立即放行 ----
# 注：`gh` 关键词纳入粗筛（feat-hitl-authz-hardening T2）——`gh pr merge` 不含 `git` 子串，
# 若不纳入会被此处提前放行、绕过下方 merge 授权硬门。
# 注：`stage7_push` 关键词纳入粗筛（feat-stage-exec-scripts T2′）——`bash .harness/scripts/stage7_push.sh …`
# 既不含 `git` 也不含 `gh` 子串，若不纳入会被此处提前放行、绕过下方 T2 push 授权硬门（本卡核心缺口）。
if [[ "$payload" != *git* && "$payload" != *gh* && "$payload" != *rm* && "$payload" != *sudo* \
   && "$payload" != *mkfs* && "$payload" != *chmod* && "$payload" != *':()'* \
   && "$payload" != *stage7_push* && "$payload" != */dev/sd* ]]; then
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
#
# T2′ 脚本执行形态识别（feat-stage-exec-scripts · AC-9 / AC-9b / AC-10 / AC-12）：
# 缺口：`bash .harness/scripts/stage7_push.sh <args>` 命令串既无 `git push` 字面、也无 `bash -c` 包裹
#   → _authz_gate 判空 → 授权硬门被整个绕过（脚本内部真正的 git push 是子进程、不经 Bash 工具、不触发 hook）。
# 闭合：把该脚本的**执行形态**识别为 push gate（只做 gate 归类，之后完全复用既有台账/词表/CONSUMED/
#   fail 边界判定链——不新增第二份判定逻辑，AC-10 判定源单一；deny 文案亦复用同一套，AC-12）。
#
# 【v3 结构性反转 · code_review_v2 M-2】判定方向从「白名单枚举执行形态、未知即放行」反转为
#   「**含脚本字面即默认归门（fail-closed），仅当被判定为只读引用才放行**」。
#   反转动机：v1/v2 两轮都是「枚举式前缀白名单」——段首 token 不在已知包裹表（env/timeout/nice/…）里
#   就放弃识别、放行。v1 抓到 5 个洞（`( )` / `{ }` / timeout / nice / `&`），补完 v2 又抓到 6 个
#   （`if …; then <X>; fi` / `if ! <X>; then` / `for … do` / `while … do` / `sudo <X>` / `xargs <X>`），
#   **同一个类的第二次泄漏**；且这些都不是对抗性改写——`if ! bash <脚本>; then echo 失败; fi` 是 shell
#   错误处理的标准写法。继续往白名单补 token 只会有第三次泄漏：**根因是判定方向反了**。
#   反转后欠匹配在**结构上归零**：任何今天没想到的包裹（`flock` / `torsocks` / `case…in` / 新关键字 /
#   明天的新语法）段首 token 都不在只读白名单里 → 默认归门，无须先有人"发现"它。
#   代价 = 过匹配（不在只读白名单里的冷门读命令要求一次授权）——取向声明允许（见下）。
#
# 判定算法（逐分段）：
#   ① 分段：切 `&&` `||` `;` `|` `&` `(` `{ ` 与换行（`$(` 先替换为占位符保护，故命令替换不被 `(` 切开
#      —— 否则 `cat $(pwd)/stage7_push.sh` 会被切出以脚本路径开头的伪段首 → 误伤 AC-9b；
#      `{ ` 带空格锚定，故 `${VAR}` 不受影响；闭括号 `)` / `}` 无须切，只出现在命令之后）。
#   ② 不含 `stage7_push.sh` 字面的分段：与本门无关，跳过。**例外 ②′**：段首是解释器/参数执行器
#      （`bash`/`sh`/`xargs`/`eval`/`source`/`.`）时归门——脚本字面在上游只读段、经管道被喂进来执行
#      （`find … -name <脚本> | xargs bash` / `ls <脚本> | xargs bash` / `grep -l … <脚本> | sh`）：
#      上游段首是只读命令会被 ⑤ 放行、下游段不含字面会被 ② 跳过 → 两头落空，故须在此堵死。
#   ③ 分段内任意位置命中「解释器 + 脚本路径」（`bash <脚本>` / `/bin/sh -x <脚本>` / `source <脚本>`）
#      → 归门（非锚定 · 压过只读白名单，堵死 `cat $(bash <脚本>)` 这类命令替换内执行；左界含引号，
#      故 `git submodule foreach 'bash <脚本>'` / `awk 'BEGIN{system("bash <脚本>")}'` 亦归门）。
#      **③′** `find … -exec|-execdir|-ok|-okdir`；**③″** 命令替换内**直接执行**（`cat $(<脚本> --branch x)`
#      / `` cat `<脚本> --branch x` ``）——段首是 `cat` 却真的执行，故须压过只读白名单。
#   ④ 剥离段首的 `VAR=val` 赋值前缀与包裹/控制流前缀（env/nohup/time/command/exec/timeout/nice/stdbuf/
#      ionice/setsid/chrt/taskset/sudo/doas/xargs/if/!/then/else/elif/do/while/until 及其选项与数值参数）。
#      注意：**该剥离表已不再承担安全职责**——它只用于**降低过匹配**（让 `timeout 5 cat <脚本>` /
#      `if grep -q x <脚本>; then` 仍能落到只读命令段首上）。表里少一个 token 只会多要一次授权，
#      **不会**再产生放行漏洞（这正是"结构性关掉整个类"与"打地鼠"的区别）。
#   ⑤ 段首 token ∈ 只读引用白名单（cat/less/head/tail/grep/sed/awk/wc/ls/stat/file/diff/chmod/cp/git/
#      test/`[`/vim/… 含 `/usr/bin/` 路径前缀形态）→ 该分段是把脚本当**数据**引用 → 不归门（读一眼
#      脚本、把它 `git add`、给它加执行位，都不该要授权 · AC-9b）。
#   ⑥ 其余一切（未知命令 / 段首即脚本路径 / `.` 点号 source / 无法判定）→ **归门**（fail-closed）。
#
# 威胁模型：继承本 hook 自声明的"纪律护栏非沙箱"口径——不承诺对抗性改写（复制改名 / eval / base64
#   解码 / 内联脚本内容 / 变量拼接出脚本路径）。取向沿用 v5：**过匹配可接受，欠匹配不可接受**。
_s7_exec=0
if [[ "$cmd" == *stage7_push.sh* ]]; then
  _s7_segs="${cmd//\$\(/\$$'\x01'}"          # 保护 $( 命令替换（占位符不含 `(`，避免被下方 `(` 分段误切）
  _s7_segs="${_s7_segs//&&/$'\n'}"
  _s7_segs="${_s7_segs//\|\|/$'\n'}"
  _s7_segs="${_s7_segs//;/$'\n'}"
  _s7_segs="${_s7_segs//|/$'\n'}"
  _s7_segs="${_s7_segs//&/$'\n'}"            # 后台/分隔 `&`（`&&` 已先行替换为换行）
  _s7_segs="${_s7_segs//(/$'\n'}"            # 子 shell `( … )` 开括号（`$(` 已被保护）
  _s7_segs=" ${_s7_segs}"                    # 前置一空格，使行首花括号组也具备下方 ` { ` 的左空格边界
  _s7_segs="${_s7_segs// \{ /$'\n'}"         # 花括号组 `{ …; }` 开括号（**左右均需空格** → `${VAR}` 与
                                             # awk 程序体 `'{ print }'`（左界是引号）均不误切）
  # ③ 解释器 + （可选选项）+ 脚本路径 —— **非锚定**（段内任意位置命中即归门；覆盖命令替换/反引号内执行）
  #    左界含 \x01（$( 保护占位符）、反引号、单/双引号 → `cat $(bash <脚本>)` / `cat \`bash <脚本>\`` /
  #    `git submodule foreach 'bash <脚本>'` / `awk 'BEGIN{system("bash <脚本>")}'` 亦归门（引号包裹的
  #    内层命令不因引号紧邻而失配——引号是最常见的内层载荷边界）
  _re_s7_interp='(^|[[:space:]]|/|'$'\x01''|`|'"'"'|")(bash|sh|zsh|dash|ksh|source)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^[:space:]]*stage7_push\.sh'
  # ③′ `find … -exec <cmd> {} …` / `-execdir` / `-ok` / `-okdir`：脚本字面在 -name 实参位、执行体在 `{}`
  #    占位符里 → 段首是只读命令（find）但实际会执行 → 段内出现该 token 即归门（压过只读白名单）
  _re_s7_exec_arg='(^|[[:space:]])-(exec|execdir|ok|okdir)([[:space:]]|$)'
  # ③″ 命令替换内**直接执行**脚本（无解释器）：`cat $(<脚本> --branch x)` / `cat \`<脚本> --branch x\``。
  #    段首 token 是只读命令（cat）→ 会被 ⑤ 放行，故须在此单独归门。
  #    左界后禁止 `)` 与反引号（`[^[:space:])\`]*`）→ `cat $(pwd)/<脚本>` 与 `cat \`pwd\`/<脚本>` 这类
  #    「命令替换出目录、脚本只是路径实参」的**只读引用**不被误伤（AC-9b）。
  _re_s7_subst_exec='('$'\x01''|`)[^[:space:])`]*stage7_push\.sh'
  # ②′ 「投喂执行器」：不含脚本字面、但段首是解释器 / 参数执行器的分段（`… | xargs bash` / `… | sh`）。
  #    脚本字面在**上游只读段**（`find -name <脚本>` / `ls <脚本>` / `grep -l … <脚本>`），经管道被喂给
  #    下游执行 → 上游段首是只读命令会被 ⑤ 放行、下游段不含字面会被 ② 跳过 → 两头落空。故：整条命令串
  #    既含脚本字面、又存在这样的执行器分段 → 归门（fail-closed）。
  _re_s7_feeder='^([^[:space:]]*/)?(bash|sh|zsh|dash|ksh|xargs|eval|source|exec|\.)$'
  # ④ 段首可剥离的包裹/控制流前缀（**非安全边界** · 仅降过匹配；缺项只会多要授权，不会放行）
  _re_s7_wrap='^(env|nohup|time|command|exec|timeout|nice|stdbuf|ionice|setsid|chrt|taskset|sudo|doas|xargs|if|then|else|elif|do|while|until|!)[[:space:]]+'
  # ⑤ 只读引用白名单（**命中才放行** · 其余一切归门）——把脚本当数据/文件对象处理的命令
  _re_s7_ro='^([^[:space:]]*/)?(cat|bat|tac|less|more|most|head|tail|grep|egrep|fgrep|zgrep|rg|ag|ack|wc|nl|od|xxd|hexdump|strings|stat|file|ls|dir|find|diff|cmp|comm|md5sum|sha1sum|sha256sum|sha512sum|shasum|cksum|sed|awk|gawk|mawk|nawk|cut|sort|uniq|tr|column|fold|shellcheck|shfmt|realpath|readlink|dirname|basename|touch|chmod|chown|chgrp|cp|mv|rm|ln|mkdir|install|git|test|\[|\[\[|vim|vi|view|nvim|nano|emacs|code|open)$'
  _s7_seg=""
  while IFS= read -r _s7_seg || [[ -n "$_s7_seg" ]]; do
    _s7_seg="${_s7_seg#"${_s7_seg%%[![:space:]]*}"}"          # 去前导空白（两类分段共用）
    _s7_haslit=0
    [[ "$_s7_seg" == *stage7_push.sh* ]] && _s7_haslit=1
    if [[ "$_s7_haslit" == "1" ]]; then
      if [[ "$_s7_seg" =~ $_re_s7_interp ]] || [[ "$_s7_seg" =~ $_re_s7_exec_arg ]] \
         || [[ "$_s7_seg" =~ $_re_s7_subst_exec ]]; then
        _s7_exec=1                                             # ③/③′/③″ 解释器执行 / find -exec / 命令替换内直接执行 → 归门
        break
      fi
    fi
    _s7_wrapped=0
    while : ; do                                               # ④ 剥离段首包裹/控制流前缀（两类分段共用）
      if [[ "$_s7_seg" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; then
        :                                                      # `VAR=val ` 赋值前缀
      elif [[ "$_s7_seg" =~ $_re_s7_wrap ]]; then
        _s7_wrapped=1                                          # 包裹/控制流前缀（env/timeout/sudo/if/…）
      elif [[ "$_s7_wrapped" == "1" && "$_s7_seg" =~ ^(-[^[:space:]]*|[0-9][^[:space:]]*)[[:space:]]+ ]]; then
        :                                                      # 仅在包裹前缀之后：吞掉其选项（-k/-n/-oL）与时长/数值参数（60 / 5s）
      else
        break
      fi
      _s7_seg="${_s7_seg#* }"                                  # 剥离一个前缀 token
      _s7_seg="${_s7_seg#"${_s7_seg%%[![:space:]]*}"}"
    done
    _s7_head="${_s7_seg%%[[:space:]]*}"                        # 段首 token（已剥离包裹前缀）
    if [[ "$_s7_haslit" == "0" ]]; then
      # ②′ 不含脚本字面的分段：段首（剥前缀后）若是解释器/参数执行器 → 脚本字面很可能经管道/实参被喂给
      #    它执行（`cat <脚本> | bash` / `cat <脚本> | env bash` / `… | timeout 60 bash`）→ 归门。
      #    **必须在 ④ 剥离之后判**：否则 `| env bash` 的段首是 `env` 而非 `bash`，一个包裹前缀即可绕过。
      if [[ -n "$_s7_head" && "$_s7_head" =~ $_re_s7_feeder ]]; then
        _s7_exec=1
        break
      fi
      continue                                                 # ② 其余不含脚本的分段 → 与本门无关
    fi
    if [[ -n "$_s7_head" && "$_s7_head" =~ $_re_s7_ro ]]; then
      continue                                                 # ⑤ 只读引用 → 该分段不归门
    fi
    _s7_exec=1                                                 # ⑥ 未知 / 执行形态 / 无法判定 → 归门（fail-closed）
    break
  done <<< "$_s7_segs"
fi

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
elif [[ "$_s7_exec" == "1" ]]; then
  # T2′：脚本执行形态 → 归入 push gate（此后判定链与直接 `git push` 完全一致）
  _authz_gate="push"
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

  # 台账定位（与 T1 写端同口径：STATE_DIR + session_id）——harness_state_root() 统一口径（方案甲 · T-B）
  _root_dir="$(harness_state_root)"
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

  # ---- 命令携带的 PR 号（fix-script-dist-and-gate-fixes · T2 幻影 PR 号修复 · AC-8/9/10/11 · v2 词元遍历）----
  # 【修前】grep -oE '#[0-9]+|merge[[:space:]]+[0-9]+|pr[[:space:]]+[0-9]+'
  #   其中 `pr[[:space:]]+[0-9]+` 是**无命令位约束的裸词元匹配**：命令里的 `--no-pr 2>&1` 被读成
  #   "pr" + "2" → 提出**幻影号 2** → 与授权台账里的真实号（#259）不一致 → 下方一致性校验判负
  #   → **合法授权被误拒**（Owner 实测：台账 PR #259 + 命令含 `--no-pr 2>&1` → push 被拦）。
  # 【v1（已废 · code_review_v1 F1）】纯正则 `gh …pr …<子命令>([[:space:]]+$_ghopt)*…#?([0-9]+)`：
  #   $_ghopt 的通配分支（`--[[:alnum:]-]+` / `-[[:alpha:]]`）**只匹配 flag 本身、不消费 flag 的值** →
  #   `gh pr merge --subject 42 259` 把 `--subject` 当布尔 flag 吃掉、再把它的值 `42` 当成号 → **提出错号 42**
  #   （真实目标是 259）。**错号比提空更危险**：台账里若恰有另一条授权 PR #42 的条目 → 号"一致" → 放行 →
  #   **拿 A 的授权合并了 B**（身份错认 = 欠匹配红线），比"提空跳过校验"的旧行为更坏。
  # 【v2 · 本实现】用**词元遍历（token walk）**替代贪婪正则。失败方向铁律（本段全部设计的唯一取舍轴）：
  #   **绝不提出一个"具体但错误"的号；拿不准就返空**——返空 = 退回既有"跳过一致性校验"语义（弱但不认错人）。
  #   ① **命令位通道**：定位 `gh` 词元（允许 `/usr/bin/gh` 路径前缀 + `bash -c "…"` / `sh -c '…'` 引号包裹）
  #      → 跳全局 flag（**取值型连值一起跳**）→ 认 `pr` → 跳 flag → 取子命令（白名单 `_pr_subs`，**刻意
  #      不含 create/list**，二者不吃 PR 号位置参数）→ 子命令之后逐词元前进找号：
  #        · **取值型 flag（`_pr_valopt`）跳 2 个词元**（flag + 它的值）；`--flag=value` 形态只跳 1 个。
  #          带空格的引号值（`--body "see 100"`）经 `_pr_q` 跨词元引号态一路吃到闭合引号 —— 这是 F1 的正解：
  #          flag 的值**永远不会**落到号位上。
  #        · **布尔型 flag（`_pr_boolopt`）跳 1 个词元** —— `gh pr merge --squash 259` / `--auto 259` 仍取到 259。
  #        · **未知 flag** → 跳 1 个词元并置 `_pr_unk=1`（它可能是取值型、其值可能就是下一个裸数字）。
  #        · `--` 裸分隔符 → 其后首个词元一律按位置参数处理。
  #        · 位置参数 → 解析 PR 号（`259` / `#259` / `"259"` / `'259'` / `https://…/pull/259`）；
  #          **解析失败即停并返空**（不再往后找，杜绝把后面某个无关数字当成号）。
  #      · **软歧义 ⇒ 提空（安全阀① · 下方 `_pr_unk=1` ⇒ `_pr_soft=1`）**：候选号紧跟在一个**未知** flag
  #        之后 → 无法确定它是"号"还是"那个未知 flag 的值" → **不采信该号（提空）**，绝不猜。
  #        **为何软歧义不 deny**：`gh pr merge --future-bool-flag 259` 是**完全合法**的命令（未知 flag 若是
  #        布尔型，259 就是真号）——deny 它会误伤合法 merge。此路径**保持 v3 既有语义（提空 → 跳过校验）**。
  #      · **硬歧义 ⇒ fail-closed DENY（安全阀② · v4 · 阶段 D · AC-10 三态第 3 态）**：`gh pr <sub>` 语法
  #        **最多接受 1 个位置参数**；若在**本 gh 调用范围内**（边界 = 命令分隔符 `; && || | &` / 重定向
  #        `> <` / 行注释 `#`）出现**第二个裸位置参数** → 号的归属不可判 → **直接 deny(exit 2) + 改正提示**。
  #        例：`gh pr merge --json number 42 259`（`--json` 吃掉 `number` 后 `42` 落到号位、真实目标 `259`
  #        被忽略）。**v3 的做法（映射为"提空"）是错的**：提空 ⇒ 跳过一致性校验 ⇒ 台账里**任何**合法授权
  #        （哪怕只授权了 #42）都能放行 #259 —— "拿 A 的授权操作 B"只是从"认错人"变成了"不检查"，并未闭合
  #        （Owner 实测坐实 · HITL-3 拍板改 AC-10 为三态）。**deny 不误伤**：两个裸位置参数是 `gh` 自身
  #        就拒绝执行的非法语法 ⇒ 没有任何合法命令落进该分支（取向：过匹配 fail-closed 可接受）。
  #        **边界**：本段整体位于 `if [[ -n "$_authz_gate" ]]` 之内 ⇒ 歧义 deny **只在命令已归入 push/merge
  #        门时**生效；未归门命令不进本段，绝不因歧义被拦。
  #      · 幻影号闸仍在：`gh pr merge --auto 2>&1` 的 `2>&1` 不是纯数字 → 不成号；`--no-pr` / `foo-pr-2.txt`
  #        根本没有 `gh` 词元 → 通道 ① 不成立（**本卡核心缺陷的那道闸**）。
  #   ② **独立 `#N`**：语义与修前**逐字节一致**（未收紧）——本通道与幻影号无关，保持零回归。
  #   顺序：① 优先（命令位的号是本次操作真正针对的 PR），① 提不到号才回退 ②。
  # 取向（沿用前置卡）：**过匹配（fail-closed）可接受、欠匹配不可接受**。三态（AC-10 · HITL-3 修订）：
  #   **提到号** → 照旧一致性校验；**提空**（命令本就没号）→ **跳过**校验（既有语义**逐字节不变**）；
  #   **硬歧义** → **deny**（新第 3 态，必须与"空"区分）。
  # bash 3.2 兼容：只用 `set --` 位置参数（本 hook 从不使用位置参数）+ `case` + 参数展开；
  #   无 `declare -A` / `mapfile` / `${v,,}`；零外部子进程（比 v1 再省 2 个 grep）。
  _cmd_pr=""
  _pr_ambiguous=0                                            # ★ 三态第 3 态（AC-10 · v4）：硬歧义 ⇒ 下方 fail-closed deny
  _re_pr_hash='#([0-9]+)'
  # 取号子命令白名单（吃 PR 号位置参数的子命令；刻意不含 create/list）
  _pr_subs=' merge view checkout close reopen ready edit comment review diff checks update-branch '
  # 取值型 flag：其后紧跟的词元是它的**值** → 必须连值一起跳过，否则值里的裸数字会被误当 PR 号（F1 根因）
  # v3（LOW-2）：对照 `gh pr merge|view|checkout|close|reopen|edit|comment|review|diff|checks --help` 的真实
  #   flag 集合复核，补齐**取值型**漏收项：`-A`（`--author-email` 短名 · merge）/ `--branch`（checkout）/
  #   `--title`（edit）/ `--milestone`（edit · 只补长名，短名 `-m` 在 merge 上是布尔 `--merge`，冲突则保守留布尔）/
  #   `--add-*`/`--remove-*`（edit）/ `--color`（diff）/ `-i --interval`（checks）。
  #   **只补取值型**：把布尔误列为取值型只会多跳 1 个词元 → 退化成"提空"（安全方向）；反之把取值型
  #   误列为布尔，其值会落到号位 → 出错号（危险方向），故布尔清单一律不扩。
  _pr_valopt=' -R --repo --hostname -t --subject -b --body -F --body-file -A --author-email --match-head-commit -c --comment -B --base -H --head -L --limit -q --jq --json --template --branch --title --milestone --add-assignee --add-label --add-project --add-reviewer --remove-assignee --remove-label --remove-project --remove-reviewer --color -i --interval '
  # 布尔型 flag：不吃值 → 只跳 1 个词元（PR 号可紧随其后）
  _pr_boolopt=' -h --help --version --admin --auto --disable-auto --dry-run -d --delete-branch -m --merge -r --rebase -s --squash -w --web --comments '
  if [[ "$cmd" == *gh* ]]; then
    set -f                                                   # 关 glob：词元切分不做路径展开（`*.txt` 不落盘扩张）
    set -- $cmd                                              # 词元化（本 hook 全程不使用位置参数，安全复用）
    set +f
    while [[ $# -gt 0 ]]; do
      # ---- 定位 `gh` 词元（剥前导引号/反引号 + 剥路径前缀）----
      _pr_t="$1"
      while :; do
        case "$_pr_t" in '"'*|"'"*|'`'*) _pr_t="${_pr_t#?}" ;; *) break ;; esac
      done
      _pr_t="${_pr_t##*/}"                                   # /usr/bin/gh → gh；docs/foo-pr-2.txt → foo-pr-2.txt
      if [[ "$_pr_t" != "gh" ]]; then shift; continue; fi
      shift
      # ---- A：跳 gh 全局 flag（取值型连值跳），认 `pr` ----
      _pr_ok=0
      while [[ $# -gt 0 ]]; do
        case "$1" in
          pr) _pr_ok=1; shift; break ;;
          --) shift ;;
          -*)
            case "$1" in
              *=*) shift; continue ;;
            esac
            case "$_pr_valopt" in
              *" $1 "*) shift; if [[ $# -gt 0 ]]; then shift; fi; continue ;;
            esac
            shift ;;
          *) break ;;
        esac
      done
      if [[ $_pr_ok -eq 0 ]]; then continue; fi              # 该 gh 不是 `gh … pr …` → 找下一个 gh 词元
      # ---- B：跳 pr 与子命令之间的 flag，取子命令 ----
      _pr_sub=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -*)
            case "$1" in
              *=*) shift; continue ;;
            esac
            case "$_pr_valopt" in
              *" $1 "*) shift; if [[ $# -gt 0 ]]; then shift; fi; continue ;;
            esac
            shift ;;
          *) _pr_sub="$1"; shift; break ;;
        esac
      done
      case "$_pr_subs" in
        *" $_pr_sub "*) : ;;
        *) continue ;;                                       # create / list / 空 → 不吃号位 → 找下一个 gh
      esac
      # ---- C：子命令之后逐词元找 PR 号（歧义即返空）----
      _pr_unk=0                                              # 上一个跳过的是否为"未知 flag"（其值可能是裸数字）
      _pr_q=""                                               # 跨词元引号态（取值型 flag 的带空格引号值）
      _pr_end=0                                              # 是否已见 `--`（其后首个词元一律按位置参数）
      _pr_soft=0                                             # 软歧义（安全阀①：号紧跟未知 flag）→ 提空（既有语义）
      _pr_hard=0                                             # 硬歧义（安全阀②：第二个裸位置参数）→ deny（AC-10 三态）
      _pr_cand=""
      _pr_raw=""                                             # 第一个裸位置参数的原始词元（安全阀② 的扫描起点/边界）
      while [[ $# -gt 0 ]]; do
        _pr_t="$1"
        if [[ -n "$_pr_q" ]]; then                           # 引号值续词元：一路吃到闭合引号为止
          case "$_pr_t" in *"$_pr_q") _pr_q="" ;; esac
          shift; continue
        fi
        if [[ $_pr_end -eq 0 ]]; then
          case "$_pr_t" in
            --) _pr_end=1; _pr_unk=0; shift; continue ;;
            -*)
              case "$_pr_t" in
                *=*) _pr_unk=0; shift; continue ;;           # --flag=value → 值已随 flag，只跳 1 个
              esac
              case "$_pr_valopt" in
                *" $_pr_t "*)                                # 取值型 → 连值一起跳（值绝不落到号位上）
                  shift
                  if [[ $# -gt 0 ]]; then
                    _pr_v="$1"
                    case "$_pr_v" in                         # 值是未闭合的引号串 → 置引号态，续吃后续词元
                      '"'*) if [[ "$_pr_v" == *'"' && ${#_pr_v} -gt 1 ]]; then :; else _pr_q='"'; fi ;;
                      "'"*) if [[ "$_pr_v" == *"'" && ${#_pr_v} -gt 1 ]]; then :; else _pr_q="'"; fi ;;
                    esac
                    shift
                  fi
                  _pr_unk=0; continue ;;
              esac
              case "$_pr_boolopt" in
                *" $_pr_t "*) _pr_unk=0; shift; continue ;;  # 布尔型 → 只跳 1 个（号可紧随其后）
              esac
              _pr_unk=1; shift; continue ;;                  # 未知 flag → 其后若紧跟裸号 = 歧义（见下）
          esac
        fi
        # 位置参数
        if [[ $_pr_unk -eq 1 ]]; then
          # ★ 安全阀①（软歧义）：号可能是那个未知 flag 的值 → **不采信**（_pr_cand 保持空 ⇒ 提空），绝不猜。
          # v4：该词元**确已占掉"第一个裸位置参数"位** → 仍记进 `_pr_raw`，交由阶段 D 继续往后找**第二个**
          # 裸位置参数（`gh pr merge --foo 42 259` 同样是"两个裸位置参数"的非法语法 ⇒ 应升级为硬歧义 deny）。
          _pr_soft=1
          _pr_raw="$_pr_t"
          break
        fi
        _pr_raw="$_pr_t"                                     # 候选号的**原始词元**（含尾随分隔符，供安全阀② 定边界）
        _pr_c="$_pr_t"
        while :; do                                          # 剥尾随的 shell 分隔符 / 引号
          case "$_pr_c" in
            *';'|*')'|*','|*'"'|*"'"|*'`') _pr_c="${_pr_c%?}" ;;
            *) break ;;
          esac
        done
        while :; do                                          # 剥前导引号 / 反引号
          case "$_pr_c" in
            '"'*|"'"*|'`'*) _pr_c="${_pr_c#?}" ;;
            *) break ;;
          esac
        done
        case "$_pr_c" in '#'*) _pr_c="${_pr_c#\#}" ;; esac   # `#259`
        case "$_pr_c" in                                     # URL 形态：https://github.com/o/r/pull/259
          http://*/pull/*|https://*/pull/*) _pr_c="${_pr_c##*/pull/}"; _pr_c="${_pr_c%%/*}" ;;
        esac
        case "$_pr_c" in
          ''|*[!0-9]*) _pr_cand="" ;;                        # 非纯数字（分支名 / `2>&1` / `$PR`）→ 停 & 返空
          *) _pr_cand="$_pr_c" ;;
        esac
        break
      done
      # ---- D：第二裸位置参数检测（★ 安全阀② · v4 = 硬歧义 ⇒ fail-closed DENY）----
      # 事实前提：`gh pr <sub>` 的语法**最多接受 1 个位置参数**（`[<number> | <url> | <branch>]`，12 个
      #   白名单子命令无一例外）。因此第一个裸位置参数之后若在**本 gh 调用范围内**还剩第二个裸位置参数，
      #   说明这条命令要么形态非法、要么我们的候选号其实是某个 flag 的值 —— 都无法确定"号是谁"。
      # 被它闭合的漏洞（评审 v2 LOW-1）：`gh pr merge --json number 42 259`
      #   —— `--json` 是 view/list 的取值型 flag（在清单内 ⇒ 安全阀① 的"未知 flag"判据不触发），它吃掉
      #      `number` 后 `42` 落到号位、真实目标 `259` 反被忽略 ⇒ v2 提出**错号 42**（若台账恰好授权
      #      #42 即误放行 = 身份错认）。
      # 【v3 → v4 的关键修正】v3 把该歧义映射为"提空"，而"提空 ⇒ 跳过一致性校验" ⇒ **歧义命令仍被放行**
      #   （台账只授权 #42 时 `gh pr merge --json number 42 259` 实测 rc=0）——只是把"认错人"换成"不检查"，
      #   "拿 A 的授权操作 B"并未闭合。v4 按 AC-10 三态改为 **deny(exit 2)**：`_pr_hard=1` ⇒ `_pr_ambiguous=1`
      #   ⇒ 下方 fail-closed 拒绝并给出可自救的改正提示。**不误伤**：两个裸位置参数本就是 `gh` 拒绝执行的
      #   非法语法，任何合法命令都不落进该分支（§不误伤正例，下）。
      # 【入口条件（v4 放宽）】只要**已消费掉第一个裸位置参数**（`_pr_raw` 非空 —— 无论它解析成号、
      #   解析失败、还是被安全阀① 判为软歧义）就往后扫，这样 `gh pr merge --foo 42 259`（软歧义 + 第二个
      #   裸位置参数）也能被判为硬歧义 deny。若压根没有位置参数（`gh pr merge --auto 2>&1`）→ 不扫 → 提空。
      # 【gh 调用范围（scope）边界】—— 越过即停止扫描，其后词元不算"第二个位置参数"：
      #   · 命令分隔符：词元以 `;` / `&` / `|` / `)` 结尾（覆盖 `;` `&&` `||` `|` `&` 及 `259;` `--squash;`
      #     `$(… 259)` 这类粘连形态）；候选号词元自身若以其结尾（`gh pr merge 259; echo 42`）则**不进入**扫描。
      #   · 重定向：词元含 `>` 或 `<`（`2>&1` / `>log` / `<in` —— 是 shell 的重定向、不是 gh 的参数）。
      #   · 行注释：词元以 `#` 开头（其后是注释文本、不是 gh 的参数）。
      # 【不误伤正例】flag 仍按 valopt(连值跳) / boolopt(跳 1) / `--flag=value`(跳 1) 解析：
      #   `gh pr merge 259 --squash`（号后布尔 flag）、`gh pr merge 259 -t "s"`（号后取值型 flag）
      #   均**不产生**第二个位置参数 ⇒ 仍提到 259。未知 flag 只跳 1 个词元，其后若紧跟裸词元则无法区分
      #   "它的值" 与 "第二个位置参数" ⇒ 按铁律判歧义返空（宁空勿错）。
      _pr_scan=1
      case "$_pr_raw" in *';'|*'&'|*'|'|*')') _pr_scan=0 ;; esac   # 第一个位置参数词元自身即范围终点 → 无须扫描
      if [[ -n "$_pr_raw" && $_pr_scan -eq 1 ]]; then
        shift                                                # 越过第一个裸位置参数词元本身
        while [[ $# -gt 0 ]]; do
          _pr_t="$1"
          if [[ -n "$_pr_q" ]]; then                         # 引号值续词元：一路吃到闭合引号为止
            case "$_pr_t" in *"$_pr_q") _pr_q="" ;; esac
            shift; continue
          fi
          case "$_pr_t" in
            *';'|*'&'|*'|'|*')') break ;;                    # 命令分隔符 → 本 gh 调用结束
            *'>'*|*'<'*) break ;;                            # 重定向 → 其后不是 gh 的参数
            '#'*) break ;;                                   # 行注释 → 本 gh 调用结束
          esac
          if [[ $_pr_end -eq 0 ]]; then
            case "$_pr_t" in
              --) _pr_end=1; shift; continue ;;
              -*)
                case "$_pr_t" in
                  *=*) shift; continue ;;                    # --flag=value → 值已随 flag
                esac
                case "$_pr_valopt" in
                  *" $_pr_t "*)                              # 取值型 → 连值一起跳（值不是位置参数）
                    shift
                    if [[ $# -gt 0 ]]; then
                      _pr_v="$1"
                      case "$_pr_v" in                       # 值是未闭合引号串 → 置引号态，续吃后续词元
                        '"'*) if [[ "$_pr_v" == *'"' && ${#_pr_v} -gt 1 ]]; then :; else _pr_q='"'; fi ;;
                        "'"*) if [[ "$_pr_v" == *"'" && ${#_pr_v} -gt 1 ]]; then :; else _pr_q="'"; fi ;;
                      esac
                      shift
                    fi
                    continue ;;
                esac
                case "$_pr_boolopt" in
                  *" $_pr_t "*) shift; continue ;;           # 布尔型 → 跳 1（不吃值 → 不产生位置参数）
                esac
                shift; continue ;;                           # 未知 flag → 跳 1；其后若紧跟裸词元 → 下方判歧义
            esac
          fi
          _pr_hard=1                                         # ★ 安全阀②：第二个裸位置参数 → 号归属不可判 → 硬歧义 deny
          break
        done
      fi
      # 三态收口（AC-10）：硬歧义 → 置 `_pr_ambiguous`（下方 deny）；否则候选号非空才采信（软歧义/解析失败 → 提空）
      if [[ $_pr_hard -eq 1 ]]; then
        _pr_ambiguous=1
        _cmd_pr=""
      elif [[ -n "$_pr_cand" ]]; then
        _cmd_pr="$_pr_cand"
      fi
      break                                                  # 已定位首个 `gh … pr <取号子命令>` → 收工
    done
  fi
  # ★ 三态第 3 态（AC-10 · HITL-3 修订）：硬歧义 ⇒ **fail-closed deny**，且不回退通道 ②（歧义是决定性的）。
  # 边界：本段位于 `if [[ -n "$_authz_gate" ]]` 之内 ⇒ 只有已归入 push/merge 门的命令才可能走到这里。
  if [[ $_pr_ambiguous -eq 1 ]]; then
    echo "[harness:pre_bash_guard] 阻断（授权硬门·${_authz_gate}·PR 号歧义）：检测到该命令的 PR 号存在歧义——\`gh pr <子命令>\` 最多接受 1 个位置参数，但命令中出现了多个裸位置参数，无法判定本次操作真正针对哪个 PR。为避免拿 A 的授权操作 B（身份错认），已按 fail-closed 拒绝。改正：请改写为 PR 号唯一的命令形态（如 \`gh pr merge 259 --squash\`）后重试；若命令里某个取值型 flag 未被本 hook 识别（其值被误当成位置参数），请改用 \`--flag=value\` 等号形态（如 \`--subject=42\`）后重试。" >&2
    exit 2
  fi
  if [[ -z "$_cmd_pr" ]] && [[ "$cmd" =~ $_re_pr_hash ]]; then
    _cmd_pr="${BASH_REMATCH[1]}"                             # ② 独立 `#N`（与修前逐字节一致 · 零回归）
  fi

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
