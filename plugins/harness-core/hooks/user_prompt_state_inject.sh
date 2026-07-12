#!/usr/bin/env bash
# UserPromptSubmit 钩子（stage-02 升级版）：每轮用户发言前注入 [harness:prompt_state] 块。
# 结构对齐 docs/stage-02 D-01 §4.2（M/K 分组主清单 + 待处理级联评估 + L 豁免注解段 + 动作指引）。
#
# 设计（stage-01 基线沿用 + stage-02 扩展）：
#   - 不阻断：任何路径始终 exit 0；注入失败不影响用户（set -uo pipefail · 不引入 -e）
#   - 只 warning 不交互（D-04 §7）；HITL 拍板归 Owner 主线程
#   - 自定位：三级回退（git → CLAUDE_PROJECT_DIR → PWD）
#   - lib / list_flows.sh 定位：三级回退链（.harness/scripts → plugins/harness-core/scripts →
#     $CLAUDE_PLUGIN_ROOT/scripts · 全不命中走内联兜底/降级行 · feat-plugin-display-parity T1）
#   - G-1 双注入守卫：经 plugin 缓存调起且项目 settings 已自注册本 hook → 静默让位 exit 0
#   - 主清单内部调 list_flows.sh --active --format=brief（D-02 §6）；hook 自身不解析 summary.md（R-5b）
#     （豁免登记：级联评估段为目录级 glob 存在性统计，不属 summary.md 解析 · spec FR-7）
#   - list_flows.sh 不可用 → 输出降级行，保留 header 与动作段
#   - 输出量受控：--brief、PASSED 不显示、L 注解 ≤3 条（D-01 §4.3）
#
# L 豁免持久化（D-12L §4.2 · HITL-1 P-1 决议）：
#   - 状态文件：.harness/state/l_exemptions.jsonl（append-only · 纳入 git 跟踪 · 每行一条 JSON）
#   - 行格式：{"timestamp":"<ISO8601>","class":"L1|L2|L3|L4","scope_summary":"<≤80字符>","source":"user-declared|owner-auto"}
#   - hook 解析用户 prompt 开头 `[流程豁免 · <类别>]` 自动追加 user-declared 记录
#     （类别映射：咨询→L1 / 文档非业务→L2 / 远程同步→L3 / 临时调试→L4；4 类之外不追加 + stderr warning）
#   - L3 owner-auto 由 Owner 按以下约定以一条 Bash 命令追加（与 hook 写入格式一致）：
#       printf '{"timestamp":"%s","class":"L3","scope_summary":"%s","source":"owner-auto"}\n' \
#         "$(date '+%Y-%m-%dT%H:%M:%S%z')" "git pull origin main" >> .harness/state/l_exemptions.jsonl
#   - 测试可注入：环境变量 L_EXEMPTIONS_FILE 覆写路径（默认真实路径），测试不污染审计文件
#   - 注解段恒输出（即使无记录显示"（无）"）—— D-12L §6.1 以"块缺少该注解段"作为 hook 失效检测信号
#   - 实现依赖：纯 grep/sed/awk，无 jq 依赖（与基线 5 个 hook 一致）
set -uo pipefail

# scope_summary 按"字符"截断（D-12L §4.2 ≤80 字符）需 UTF-8 locale；
# 容器内 LANG 指向的 locale 可能未安装（回退 C → 字节截断会切坏 CJK 字符），优先固定 C.UTF-8，不可用时退化为字节截断。
if locale -a 2>/dev/null | grep -qixE 'C\.(utf8|utf-8)'; then
  export LC_ALL=C.UTF-8
fi

# resolve_root / frontmatter status 解析单点化于 lib/（TG-1）。lib 与 list_flows.sh 定位
# 改为三级回退链（feat-plugin-display-parity T1 · 对齐 session_start_wiki_freshness.sh 先例；
# 原 $_HOOK_DIR/../.. 相对推导仅对 .claude/hooks/ 布局成立，plugin 缓存位置下失效）：
#   ① $TOP/.harness/scripts/…（消费方安装态落盘副本 / 本仓）
#   ② $TOP/plugins/harness-core/scripts/…（本仓开发态）
#   ③ $CLAUDE_PLUGIN_ROOT/scripts/…（plugin 包内直读 · 先判 CLAUDE_PLUGIN_ROOT 非空，
#      防拼出假路径 · 承 failure-record-001）
#   ④ 全不命中 → 既有内联兜底（resolve_root / _eval_status 内联版 · AC-1.4 优雅降级不崩）
# $TOP 先于 lib 探测以内联三层 fallback（git → CLAUDE_PROJECT_DIR → PWD）推得；
# _HOOK_DIR 取物理路径（pwd -P · 禁 realpath），兼作 G-1 双注入守卫的自身位置判据。
_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P || true)"

_hook_resolve_top() {
  # $TOP 内联推导（git → CLAUDE_PROJECT_DIR → PWD）——与 resolve_root 同逻辑；
  # 仅供 lib/list_flows 三级链探测与 G-1 守卫，不替代主流程 resolve_root。
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then
    printf '%s\n' "$top"
    return 0
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  printf '%s\n' "$PWD"
}
_HOOK_TOP="$(_hook_resolve_top)"

_locate_script() {
  # $1 = 相对 scripts/ 的路径；$2 = 探测基根（缺省 $_HOOK_TOP · emit_main_list 传入
  # 函数入参 $root 以保持既有可测注入性）。按三级链探测，首个可读输出绝对路径返回 0；
  # 全不命中返回 1（调用方走 ④ 内联兜底 / 既有降级行）。
  local rel="$1" base="${2:-$_HOOK_TOP}" c
  for c in "$base/.harness/scripts/$rel" \
           "$base/plugins/harness-core/scripts/$rel" \
           "${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/scripts/$rel}"; do
    if [ -n "$c" ] && [ -r "$c" ]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

_SU_LIB="$(_locate_script lib/shell-utils.sh || true)"
_FM_LIB="$(_locate_script lib/frontmatter.sh || true)"
[ -n "$_SU_LIB" ] && [ -r "$_SU_LIB" ] && . "$_SU_LIB"
[ -n "$_FM_LIB" ] && [ -r "$_FM_LIB" ] && . "$_FM_LIB"

if ! type resolve_root >/dev/null 2>&1; then
  # 内联兜底（lib 缺失时）——与 lib/shell-utils.sh resolve_root 逐字等价
  resolve_root() {
    local top
    top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$top" ]; then
      printf '%s\n' "$top"
      return 0
    fi
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
      printf '%s\n' "$CLAUDE_PROJECT_DIR"
      return 0
    fi
    printf '%s\n' "$PWD"
  }
fi

# ---------- L 豁免读写函数（可被 source 单测 · 路径经 L_EXEMPTIONS_FILE 覆写）----------

l_file_path() {
  printf '%s' "${L_EXEMPTIONS_FILE:-${root:-$(resolve_root)}/.harness/state/l_exemptions.jsonl}"
}

l_sanitize_scope() {
  # 控制字符剔除 → ≤80 字符截断 → 反斜杠/引号转义（保证 JSONL 行合法）。
  # 顺序：先截断后转义（code_review_v1 LOW-3）——避免截断点落在转义序列中间产生孤立 `\` 的非法 JSON。
  local s
  s="$(printf '%s' "$1" | tr -d '\n\r\t')"
  if [ "${#s}" -gt 80 ]; then s="${s:0:79}…"; fi
  printf '%s' "$s" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

l_append_exemption() {
  # $1=class(L1..L4) $2=scope_summary $3=source(user-declared|owner-auto)
  local f
  f="$(l_file_path)"
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  printf '{"timestamp":"%s","class":"%s","scope_summary":"%s","source":"%s"}\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "$(l_sanitize_scope "$2")" "$3" >> "$f" 2>/dev/null || true
}

l_read_recent() {
  # 末 3 条 · 新者在前；文件缺失/不可读返回 1
  local f
  f="$(l_file_path)"
  [ -r "$f" ] || return 1
  # 倒序：tac 为 GNU coreutils（macOS 无）→ POSIX awk 倒序（fix-bash32-compat B 卡 X-1/P-2）
  tail -n 3 "$f" 2>/dev/null | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}'
}

l_class_label() {
  case "$1" in
    L1) printf 'L1 咨询' ;;
    L2) printf 'L2 文档非业务' ;;
    L3) printf 'L3 远程同步' ;;
    L4) printf 'L4 临时调试' ;;
    *) printf '%s' "$1" ;;
  esac
}

l_map_category() {
  # 中文类别 → L 枚举（4 类全收 · 含显式 L3 · spec FR-8 v1.1）；不在 4 类内输出空串
  case "$1" in
    咨询) printf 'L1' ;;
    文档非业务) printf 'L2' ;;
    远程同步) printf 'L3' ;;
    临时调试) printf 'L4' ;;
    *) printf '' ;;
  esac
}

l_render_line() {
  # $1 = JSONL 行 → "- <ts> · <class label> · <scope> · source: <source>"；解析失败返回 1
  local line="$1" ts cls scope src
  ts="$(printf '%s' "$line" | sed -n 's/.*"timestamp"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cls="$(printf '%s' "$line" | sed -n 's/.*"class"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  # BRE 交替 \| 为 GNU sed 扩展（BSD sed 下提取恒空）→ 改 ERE -E（BSD/GNU 两端一致 · fix-bash32-compat B-6）
  scope="$(printf '%s' "$line" | sed -n -E 's/.*"scope_summary"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p')"
  src="$(printf '%s' "$line" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  if [ -z "$ts" ] || [ -z "$cls" ] || [ -z "$src" ]; then
    return 1
  fi
  printf -- '- %s · %s · %s · source: %s' "$ts" "$(l_class_label "$cls")" "${scope:-—}" "$src"
}

l_handle_prompt() {
  # $1 = 用户 prompt（自 stdin JSON 提取）；开头 `[流程豁免 · <类别>]` → 追加 user-declared 记录
  local prompt="$1" category cls scope
  case "$prompt" in
    "[流程豁免 · "*) ;;
    *) return 0 ;;
  esac
  category="$(printf '%s' "$prompt" | sed -n 's/^\[流程豁免 · \([^]]*\)\].*/\1/p')"
  [ -n "$category" ] || return 0
  cls="$(l_map_category "$category")"
  if [ -z "$cls" ]; then
    printf 'warning: [harness:prompt_state] L 豁免类别「%s」不在 4 类封闭枚举（咨询/文档非业务/远程同步/临时调试）内，未登记；4 类之外默认进 K 流程（D-12L §5.3）\n' "$category" >&2
    return 0
  fi
  scope="$(printf '%s' "$prompt" | sed 's/^\[[^]]*\][[:space:]]*//')"
  l_append_exemption "$cls" "${scope:-（未复述范围）}" "user-declared"
}

# ---------- 注入渲染 ----------

emit_header() {
  printf '%s\n' "[harness:prompt_state] 流程状态自检（每轮注入）"
  printf '%s\n' "  入口契约：见 CLAUDE.md §'第一动作契约'。本块为契约的当前状态镜像，**两者冲突时以严格者为准**。"
}

emit_actions() {
  printf '%s\n' "  动作（按用户 prompt 隐式/显式选择流程实例 / 通道）："
  printf '%s\n' "    · 修改类请求（业务代码 / spec / 设计文档实质内容）→ 识别属于哪个 M/K 活跃实例 + 推进；或建新实例（无活跃实例时第一步 = 复制 _TEMPLATE/ 建变更目录并初始化 summary.md，进入阶段 1）"
  printf '%s\n' "    · 非修改类（4 类豁免：L1 咨询·读代码 / L2 文档非业务 / L3 远程同步 / L4 临时调试）→ 走 L 通道，响应开头声明 \`[流程豁免 · <类别>]\` 并复述范围"
  printf '%s\n' "      · L1/L2/L4 须用户显式声明；L3 远程同步可由 Owner 主动声明（触发 3 条件见 12-L 通道定义 §3）"
  printf '%s\n' "    · 4 类之外 = 不豁免 · 默认进 K 流程（B3 类型有限枚举 · 见 12-L 通道定义 §5.3）"
}

emit_l_section() {
  printf '%s\n' "  最近 L 豁免（参考 · 单轮不传染 · 主清单之外 · 弱视觉）："
  local f lines line rendered any=0 fail=0
  f="$(l_file_path)"
  if [ ! -e "$f" ]; then
    printf '%s\n' "    （无）"
    return 0
  fi
  lines="$(l_read_recent || true)"
  if [ -z "$lines" ]; then
    if [ -r "$f" ]; then
      printf '%s\n' "    （无）"
    else
      printf '%s\n' "    （记录不可用）"
    fi
    return 0
  fi
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if rendered="$(l_render_line "$line")"; then
      printf '    %s\n' "$rendered"
      any=1
    else
      fail=1
    fi
  done <<< "$lines"
  if [ "$any" = "0" ]; then
    if [ "$fail" = "1" ]; then
      printf '%s\n' "    （记录不可用）"
    else
      printf '%s\n' "    （无）"
    fi
  fi
}

# _eval_status <file>：从首个 frontmatter（---…---）区块内提取 `status:` 值（去空格 · 小写）。
# 口径单点化于 lib/frontmatter.sh fm_status（TG-1）；lib 已 source 则别名委派，否则内联兜底
# （bash 3.2 兼容：纯 awk 解析，无关联数组 / 无 bash4 语法。缺失/解析失败 → 空串，调用方按 open 计入）。
if type fm_status >/dev/null 2>&1; then
  _eval_status() { fm_status "$1"; }
else
  _eval_status() {
    awk '
      NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }   # 无 frontmatter
      NR==1 { infm=1; next }
      infm && $0 ~ /^---[[:space:]]*$/ { exit }       # frontmatter 结束
      infm && $0 ~ /^[[:space:]]*status[[:space:]]*:/ {
        sub(/^[[:space:]]*status[[:space:]]*:[[:space:]]*/, "")
        sub(/[[:space:]]+$/, "")
        print tolower($0); exit
      }
    ' "$1" 2>/dev/null
  }
fi

# _eval_is_resolved <file>：status ∈ {resolved,closed,done} → 0（已闭合 · 跳过）；否则 1（计入 · 含缺失/open）
_eval_is_resolved() {
  case "$(_eval_status "$1")" in
    resolved|closed|done) return 0 ;;
    *) return 1 ;;
  esac
}

emit_cascade_section() {
  # 数据源（spec FR-7 v1.1）：glob proj-*/cascade_evaluations/eval_*.md，按 frontmatter status 过滤未闭合项
  # （chore-cascade-eval-schema：resolved → 跳过；open/缺失/解析失败 → 计入，保守暴露）。
  # 关联数组为 bash 4.0+（macOS 3.2 报 local: -A: invalid option）→ 平行数组线性查找（N 小）；
  # 输出取首现序（glob 已排序故确定），替代旧版 ${!by_parent[@]} 哈希序（fix-bash32-compat B-4 / R-6）
  local changes_dir="$1" f parent i found
  local -a parent_names=() parent_counts=()
  shopt -s nullglob
  for f in "$changes_dir"/proj-*/cascade_evaluations/eval_*.md; do
    _eval_is_resolved "$f" && continue   # 已闭合级联 → 不计入"待处理"
    parent="$(basename "$(dirname "$(dirname "$f")")")"
    found=-1
    i=0
    while [ "$i" -lt "${#parent_names[@]}" ]; do
      if [ "${parent_names[$i]}" = "$parent" ]; then found="$i"; break; fi
      i=$((i + 1))
    done
    if [ "$found" -ge 0 ]; then
      parent_counts[$found]=$(( ${parent_counts[$found]} + 1 ))
    else
      parent_names+=("$parent")
      parent_counts+=(1)
    fi
  done
  if [ "${#parent_names[@]}" -eq 0 ]; then
    printf '%s\n' "  待处理级联评估：无"
    return 0
  fi
  printf '%s\n' "  待处理级联评估："
  i=0
  while [ "$i" -lt "${#parent_names[@]}" ]; do
    printf '    · 来自 %s · 未闭合 %s 项（按 status 过滤未 resolved）\n' "${parent_names[$i]}" "${parent_counts[$i]}"
    i=$((i + 1))
  done
}

emit_main_list() {
  # 主清单：调 list_flows.sh --active --format=brief（D-02 §6）；失败 → 降级行 + 返回
  local root="$1" lf brief="" lf_ok=0 line state items item group
  local -a meta_lines=() ten_lines=() unknown_lines=()
  # list_flows.sh 同链定位（复用 _locate_script · 基根取入参 $root）；全不命中 → 既有降级行
  lf="$(_locate_script list_flows.sh "$root" || true)"
  if [ -n "$lf" ] && [ -f "$lf" ]; then
    if brief="$(bash "$lf" --active --format=brief 2>/dev/null)"; then
      lf_ok=1
    fi
  fi
  if [ "$lf_ok" != "1" ]; then
    printf '%s\n' "  ⚠️ list_flows 不可用 · 流程清单降级省略（修复 .harness/scripts/list_flows.sh 后恢复）"
    return 0
  fi

  if [ -z "$brief" ]; then
    printf '%s\n' "  当前活跃流程实例：无"
    return 0
  fi

  # P-5 保留行取数：自 --brief 行（FR-5 契约）受控解析，不回退解析 summary.md
  local total_active=0 single_item="" single_group="" single_state=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      meta\[*) group="meta"; meta_lines+=("$line") ;;
      ten-stage\[*) group="ten-stage"; ten_lines+=("$line") ;;
      unknown\[*) group="unknown"; unknown_lines+=("$line") ;;
      *) continue ;;
    esac
    state="$(printf '%s' "$line" | sed -n 's/^[a-z-]*\[\([^]]*\)\].*/\1/p')"
    items="${line#*]: }"
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      total_active=$((total_active + 1))
      single_item="$item"; single_group="$group"; single_state="$state"
    done < <(printf '%s\n' "$items" | awk '{gsub(/ \/ /, "\n"); print}')
  done <<< "$brief"

  printf '%s\n' "  活跃流程实例清单（按类型分组 · 主清单）："
  printf '%s\n' "    [M · 元流程]"
  emit_group_items "${meta_lines[@]:-}"
  printf '%s\n' "    [K · 10 阶段]"
  emit_group_items "${ten_lines[@]:-}"

  # P-5 保留行（HITL-1 P-5 决议：K 组下的附加提示行 · 渲染于 unknown 段之前 —— code_review_v1 LOW-2）
  # P-5 保留行 1：多活跃歧义警告（stage-01 既有）
  if [ "$total_active" -gt 1 ]; then
    printf '      ⚠️ 多个活跃实例（共 %s 个）：请用户明确本轮针对哪一个；在明确目标实例前，禁止编辑业务代码\n' "$total_active"
  fi
  # P-5 保留行 2：单活跃 10 阶段实例且阶段 <3 → 禁编辑业务代码（next_stage 沿用基线：活跃态 state 非 PASSED → next_stage = 当前阶段）
  if [ "$total_active" -eq 1 ] && [ "$single_group" = "ten-stage" ]; then
    local stage_num
    stage_num="$(printf '%s' "$single_item" | sed -n 's/.*阶段 \([0-9][0-9]*\).*/\1/p')"
    if [ -n "$stage_num" ] && [ "$stage_num" -lt 3 ]; then
      printf '%s\n' "      · 禁止：阶段 3（编码实现）开始前编辑 demo/**、harnessdemo/**、src/** 业务代码（即：阶段 2 评审通过后方可编码 · 当前 ${single_item} · ${single_state}）"
    fi
  fi

  if [ "${#unknown_lines[@]}" -gt 0 ]; then
    printf '%s\n' "    [⚠️ 未注册前缀（unknown · 前缀注册表见 D-04 §2）]"
    emit_group_items "${unknown_lines[@]:-}"
  fi
}

m0_5_next_step() {
  # $1 = brief item 文本；若携带 `（m0_5: <state>）` 标签则输出该阶段位"下一步"提示，否则空。
  # 数据来源 = list_flows --brief 行携带的 M0.5 标签（OQ-1 方案 A：hook 仅渲染、不解析 summary · R-5b）。
  # RUN → 待出口门禁；PASSED/SKIP（阶段位已结）→ 进 M1。
  local item="$1" m05state
  m05state="$(printf '%s' "$item" | sed -n 's/.*（m0_5: \([^）]*\)）.*/\1/p')"
  [ -n "$m05state" ] || return 0
  case "$m05state" in
    RUN) printf '        ↳ M0.5 RUN 中 → 待出口门禁\n' ;;
    PASSED|SKIP) printf '        ↳ M0.5 已结 → 进 M1\n' ;;
  esac
}

emit_group_items() {
  # 参数 = 该组的 brief 行集合：`group[STATE]: item1 / item2` → 逐项 `· item · STATE`
  local line state items item shown=0
  for line in "$@"; do
    [ -z "$line" ] && continue
    state="$(printf '%s' "$line" | sed -n 's/^[a-z-]*\[\([^]]*\)\].*/\1/p')"
    items="${line#*]: }"
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      printf '      · %s · %s\n' "$item" "$state"
      m0_5_next_step "$item"
      shown=1
    done < <(printf '%s\n' "$items" | awk '{gsub(/ \/ /, "\n"); print}')
  done
  [ "$shown" = "0" ] && printf '%s\n' "      （无）"
  return 0
}

emit_wiki_nudge() {
  # A-3 落点② · wiki 采纳 salience 软提示（RM-2026-124 · ADR-009 §修订 v2）：
  #   只追加一行非阻塞软提示文本（纯 printf），人读软提示·可无视。
  #   红线：非新增 PreToolUse hook · 不消费工具输出 · 不改 Read/Grep 可用性 · 不改退出码路径（恒 exit 0）。
  printf '%s\n' "  📚 wiki 提示（软·可无视）：若本轮是跨篇知识问答 / 跨多篇提炼综合题，可先 \`wiki-query\`（字面 / 单点溯源仍走 grep）。"
  return 0
}

# ---------- 常驻契约会话哨兵检测 + 兜底补注入（chore-l1-slim-and-tier-v3-20260712 · T8.3 · P4）----------
# SessionStart 的 session_start_resident_contract.sh 注入成功落 session-keyed 哨兵；本 hook 每轮检测，
# 缺失 → prompt_state 报警 + 兜底补注入（cat 权威源全文一次 · 与主注入同源 · UQ-7）+ 落哨兵防每轮重复。
# 恒不改退出码路径（永不阻断）。注入源三级回退链与主注入同口径（目录级 · 首个"四文件全可读"即用）。

_upi_contract_all_readable() {
  [ -r "$1/agents/application-owner.md" ] \
    && [ -r "$1/rules/工程结构.md" ] \
    && [ -r "$1/rules/开发流程规范.md" ] \
    && [ -r "$1/rules/项目编码规范.md" ]
}

_upi_locate_contract_base() {
  # $1=root ; 三级回退链 .harness/ → plugins/harness-core/ → $CLAUDE_PLUGIN_ROOT，首个四文件全可读即用
  local top="$1"
  if _upi_contract_all_readable "$top/.harness"; then printf '%s' "$top/.harness"; return 0; fi
  if _upi_contract_all_readable "$top/plugins/harness-core"; then printf '%s' "$top/plugins/harness-core"; return 0; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && _upi_contract_all_readable "${CLAUDE_PLUGIN_ROOT}"; then
    printf '%s' "${CLAUDE_PLUGIN_ROOT}"; return 0
  fi
  return 1
}

emit_contract_fallback() {
  # $1=root $2=sentinel_path ; cat 权威源全文一次（UQ-9 序）+ 落哨兵防重复
  local root="$1" sentinel="$2" base f
  base="$(_upi_locate_contract_base "$root" || true)"
  if [ -z "$base" ]; then
    printf '%s\n' "  ⚠️ [harness:resident_contract] 兜底注入源四文件不全可读（三级回退链均未凑齐），跳过兜底（A 类契约仍在 CLAUDE.md 恒重载 · 非契约真空）"
    return 0
  fi
  printf '%s\n' ""
  printf '%s 会话哨兵缺失 → UserPromptSubmit 兜底补注入完整调度契约（一次性·非每轮 · 约束力等同 CLAUDE.md · 源 base=%s）：\n' "[harness:resident_contract]" "$base"
  for f in "$base/agents/application-owner.md" "$base/rules/工程结构.md" "$base/rules/开发流程规范.md" "$base/rules/项目编码规范.md"; do
    printf '\n─── 以下源自 %s ───\n\n' "$f"
    cat "$f" 2>/dev/null || printf '（读取失败：%s）\n' "$f"
  done
  mkdir -p "$(dirname "$sentinel")" 2>/dev/null || true
  [ -f "$(dirname "$sentinel")/.gitignore" ] || printf '*\n' > "$(dirname "$sentinel")/.gitignore" 2>/dev/null || true
  touch "$sentinel" 2>/dev/null || true
}

# ---------- G-1 双注入守卫（spec §3 T1 · 缓解 R3 双注册点同时生效）----------

_g1_should_yield() {
  # $1 = $TOP。判据：自身脚本物理路径不在 $TOP 之下（= 经 plugin 缓存被调起），且
  # $TOP/.claude/settings.json 或 settings.local.json 任一文件已含 user_prompt_state_inject
  # 注册字样 → 返回 0（项目注册为准 · 调用方静默 exit 0）。
  # grep 失败 / 两文件均缺失 / 路径推导失败 → 返回 1（fail-open 正常注入）。
  # 物理路径经 pwd -P 推得（禁 realpath · macOS/bash 3.2 无该命令）；
  # 仅主流程执行路径调用，source 模式（单测）不受影响。
  local top="$1" top_phys f
  [ -n "$_HOOK_DIR" ] || return 1
  top_phys="$(cd "$top" 2>/dev/null && pwd -P || true)"
  [ -n "$top_phys" ] || return 1
  case "$_HOOK_DIR/" in
    "$top_phys"/*) return 1 ;;
  esac
  for f in "$top_phys/.claude/settings.json" "$top_phys/.claude/settings.local.json"; do
    if [ -f "$f" ] && grep -q 'user_prompt_state_inject' "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# ---------- 主流程 ----------

main() {
  root="$(resolve_root)"

  # G-1 双注入守卫：置于 emit 前、且先于 stdin L 追加——双活场景下让位副本若已消费
  # stdin 追加豁免记录，会与项目注册副本重复登记（append-only 审计文件双写），故整体让位。
  if _g1_should_yield "$root"; then
    exit 0
  fi

  local changes_dir="$root/.harness/changes"

  # stdin（UserPromptSubmit JSON）读取：不阻塞——tty 直跑不读；空/非 JSON/EOF → 跳过 L 追加，其余注入正常
  local stdin_raw="" prompt_val=""
  if [ ! -t 0 ]; then
    stdin_raw="$(cat 2>/dev/null || true)"
  fi
  if [ -n "$stdin_raw" ]; then
    prompt_val="$(printf '%s' "$stdin_raw" | tr -d '\n\r' \
      | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 \
      | sed -E 's/^"prompt"[[:space:]]*:[[:space:]]*"//; s/"$//')"
  fi
  if [ -n "$prompt_val" ]; then
    l_handle_prompt "$prompt_val" || true
  fi

  # 常驻契约会话哨兵检测（T8.3 · P4）：session-keyed（session_id 自 stdin payload · 与写端同口径）
  local _state_dir="${HARNESS_STATE_DIR:-$root/.harness/state}" _sid="nosid" _upi_sid _sentinel _contract_missing=0
  if [ -n "$stdin_raw" ]; then
    _upi_sid="$(printf '%s' "$stdin_raw" | tr -d '\n\r' \
      | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 \
      | sed -E 's/^"session_id"[[:space:]]*:[[:space:]]*"//; s/"$//')"
    [ -n "$_upi_sid" ] && _sid="$(printf '%s' "$_upi_sid" | tr -cd 'A-Za-z0-9._-')"
  fi
  _sentinel="$_state_dir/.resident_contract_injected_${_sid}"
  [ -f "$_sentinel" ] || _contract_missing=1

  emit_header
  printf '%s\n' "  仓库根：$root"
  if [ "$_contract_missing" = "1" ]; then
    printf '%s\n' "  ⚠️ [harness:resident_contract] 会话哨兵缺失（SessionStart 注入未生效/被压缩）→ 本轮兜底补注入完整调度契约（附于块末·一次性）。A 类决策契约仍在 CLAUDE.md 恒重载。"
  fi
  printf '\n'

  if [ ! -d "$changes_dir" ]; then
    printf '%s\n' "  状态：未定位到 .harness/changes/（已尝试 git 根 / CLAUDE_PROJECT_DIR / PWD）。"
  else
    emit_main_list "$root"
  fi
  printf '\n'
  emit_cascade_section "$changes_dir"
  printf '\n'
  emit_l_section
  printf '\n'
  emit_actions
  printf '\n'
  emit_wiki_nudge
  # 兜底补注入置于块末（哨兵缺失时 · 一次性落哨兵防每轮重复）
  if [ "$_contract_missing" = "1" ]; then
    emit_contract_fallback "$root" "$_sentinel"
  fi
  exit 0
}

# source 守卫（tasks 评审 v1 #1）：被 source 时仅定义函数（供单测），不执行主流程
if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  main
fi
