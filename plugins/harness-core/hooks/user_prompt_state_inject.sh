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
    # 阶段号解析口径单源（chore-hook-governance-hardening-20260715 · T-2 · AC-2.1）：
    # 抽为 _upi_item_stage，与 emit_stage_reconcile 快照第2列同源，消除双解析漂移。
    stage_num="$(_upi_item_stage "$single_item")"
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

# ---------- 用户授权台账落盘（feat-hitl-authz-hardening · T1 · AC-1）----------
# 每轮把真实用户 prompt 原文 + ISO8601 时间戳追加写入 $STATE_DIR/user_prompts_<sid>.log（append-only · 一行一条）。
# 该台账是 T2（merge/push 授权硬门）的证据源——由本 hook 在真实用户输入时落盘，正常流程模型不触碰（纪律性护栏非对抗沙箱，蓄意伪造面见 DF-015 R-2）。
# fail-open（AC-1）：任何异常 return 0，绝不影响既有 prompt_state 注入功能（set -uo pipefail · 无 -e）。
# 行格式：<ISO8601>\t<单行化 prompt>（jq 优先取完整原文并压单行；无 jq 退回词法提取 + 换行归一）。
append_user_prompt_ledger() {
  # $1=stdin_raw $2=state_dir $3=sid
  local raw="$1" sdir="$2" sid="$3" fullprompt="" ts f
  [ -n "$raw" ] || return 0
  sid="$(printf '%s' "${sid:-nosid}" | tr -cd 'A-Za-z0-9._-')"
  [ -n "$sid" ] || sid="nosid"
  if command -v jq >/dev/null 2>&1; then
    # jq -r（raw · 发现③）：取真「原文」裸文本，不带 JSON 外层引号 / 不留 `\n` 转义序列。
    # 兼容双字段名：真实 UserPromptSubmit 载荷 `.prompt`，另兜底 `.user_prompt` 别名。
    fullprompt="$(printf '%s' "$raw" | jq -r '.user_prompt // .prompt // empty' 2>/dev/null || true)"
  fi
  if [ -z "$fullprompt" ]; then
    # 退化：词法提取（可能截断至首个引号，尽力而为）
    fullprompt="$(printf '%s' "$raw" | tr -d '\n\r' \
      | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 \
      | sed -E 's/^"prompt"[[:space:]]*:[[:space:]]*//')"
  fi
  [ -n "$fullprompt" ] || return 0
  # 单行化兜底（顺序依据 · D-1）：残留换行/回车/制表 → 空格。**必须置于前缀过滤之前**——
  # 否则 fullprompt 以换行开头时（如 `\n<task-notification>…`），下方 `sed 's/^[[:space:]]+//'`
  # 逐行 trim 吃不掉前导 `\n`，_pf_trimmed 仍以换行开头 → case 前缀不匹配 → 伪授权面绕过落盘
  # （v3 delta 评审 D-1）。先把换行归一为空格，trim 即可吃掉前导空白、前缀匹配才生效。
  # 兼职保证一行一条：tab 同归一，避免污染 `<ts>\t<prompt>` 台账的 tab 分隔结构（append-only · 发现③）。空串上方已 return。
  fullprompt="$(printf '%s' "$fullprompt" | tr '\n\r\t' '   ')"
  # 系统通知轮前缀过滤（feat-hitl-authz-hardening · §9 · 伪授权面）：以下模式开头的轮次经
  # UserPromptSubmit 通道进来但**非真实用户输入**（后台 agent 结果 / 系统通知 / 本地命令回显），
  # 若其正文含授权样式文字会让 T2 门误命中 = 伪授权面。故 trim 前导空白后按前缀跳过不落盘。
  # 方向：fail-closed（只会少记；漏记导致 deny 可由用户重说一句授权补救，绝不多记）。
  local _pf_trimmed
  _pf_trimmed="$(printf '%s' "$fullprompt" | sed -E 's/^[[:space:]]+//')"
  case "$_pf_trimmed" in
    '<task-notification>'*|'[SYSTEM NOTIFICATION'*|'<local-command-stdout>'*|'<command-name>'*|'<local-command-caveat>'*)
      return 0 ;;
  esac
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || true)"
  [ -n "$ts" ] || return 0
  mkdir -p "$sdir" 2>/dev/null || return 0
  # 自忽略（对齐 .harness/state 既有惯例 · 用户 prompt 原文含敏感内容不入 git · UQ-4）
  [ -f "$sdir/.gitignore" ] || printf '*\n' > "$sdir/.gitignore" 2>/dev/null || true
  f="$sdir/user_prompts_${sid}.log"
  printf '%s\t%s\n' "$ts" "$fullprompt" >> "$f" 2>/dev/null || return 0
}

# ---------- 上下文水位（T-A1 · feat-segmentation-and-statedir-fix-20260714）----------
# compute_water_sum <transcript_path>：取 transcript 最后一条 assistant 消息的
#   usage.cache_read_input_tokens + usage.cache_creation_input_tokens 之和（原始 token 数）。
# 口径 = 40 卡扫描标定同源（U-5 · cache_read+cache_creation，不叠加 input_tokens）。
# fail-open（AC-A1-2）：jq 缺 / transcript 不可读 / 无 assistant / usage 缺 / 和为 0 → 返回 1（调用方跳过该行）。
compute_water_sum() {
  local tp="$1" usage cr cc sum
  [ -n "$tp" ] && [ -r "$tp" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  # 末 200 行内最后一条带 usage 的 assistant 消息（与 batch_echo 取 message 同法 · tail 限行防大文件）
  usage="$(tail -n 200 "$tp" 2>/dev/null \
    | jq -rc 'select(.type=="assistant") | select(.message.usage != null) | .message.usage' 2>/dev/null \
    | tail -n 1)"
  [ -n "$usage" ] || return 1
  cr="$(printf '%s' "$usage" | jq -r '.cache_read_input_tokens // 0' 2>/dev/null || echo 0)"
  cc="$(printf '%s' "$usage" | jq -r '.cache_creation_input_tokens // 0' 2>/dev/null || echo 0)"
  case "$cr" in ''|*[!0-9]*) cr=0 ;; esac
  case "$cc" in ''|*[!0-9]*) cc=0 ;; esac
  sum=$(( cr + cc ))
  [ "$sum" -gt 0 ] || return 1
  printf '%s' "$sum"
}

# ---------- 分段建议 + T4 事后对账（chore-hook-governance-hardening-20260715 · T-2/T-3 · 旁路恒 exit 0）----------
# 【背景 · 失效②退役寄生记号】原 T-A2「方案 P」以 stage_progress_<sid> 记号承载「本会话内阶段翻牌」信号，
#   记号由 pretool_summary_flip_guard.sh 放行路径的 _seg_write_marker 副作用写入——该副作用寄生在 T4 翻牌门
#   hook 内，一旦 T4 门被 Bash `sed -i` 绕过（门只注册 Edit|Write），记号一并静默失效 → 分段建议永不触发。
#   本卡改为「读盘阶段号快照差分对账」：不再依赖任何 hook 副作用记号，任何通道（Edit/sed/子Agent/跨会话）
#   改 summary 都能在下一轮读盘被对出。寄生段（_seg_detect_and_mark/_seg_write_marker/_seg_has_phase/
#   SEG_FLIP_RE_2/6 及主流程调用）已在 pretool_summary_flip_guard.sh 内删除（AC-2.6 · 门禁判定式一字不动）。
#
# 【T-2 分段建议 · 快照差分】每轮为各活跃 ten-stage 卡落阶段快照 last_seen_stage_<sid>.log，
#   冻结三列 schema `<card_dir>\t<当前阶段号>\t<已PASSED的1/3/5阶段集csv(可空)>`
#   （第2列供 T-2 边界差分、第3列供 T-3 翻牌差分 · AC-2.1）。当前阶段号解析复用主清单 emit_main_list 同一口径
#   （_upi_item_stage · 消除双解析漂移）；第3列用与 T4 翻牌门同族的行匹配（UPI_FLIP_RE_1/3/5 复刻 FLIP_RE_1/3/5）判定。
#   读写次序定死：每轮先读旧快照对账（T-2 边界 + T-3 报警），后覆盖写新快照——写先于比较则跨越永不可测。
#   允许切点白名单仅 2 处：2→3（HITL-2 决议后）/ 6→7（阶段6 闭合后）（AC-2.2）。阈值 env 可调（AC-2.3 · 禁写死）：
#   HARNESS_SEGMENT_T2 默认 160000 / HARNESS_SEGMENT_T6 默认 200000；env 未设/空/非数字 → 回退默认。
#   边界触发：某活跃卡当前阶段号相对上轮快照 ≤2→≥3 / ≤6→≥7 ∧ 水位≥对应阈值 → 注入分段建议；多卡同轮
#   跨越逐卡各注入一次（AC-2.2 · 去重键 card|boundary 天然按卡隔离）。首轮/纯查询/未推卡：无旧快照基线 → 零建议（AC-2.5）。
#   单次去重（AC-2.4）：同一边界事件（卡+边界）仅建议一次（keyfile segment_suggest_fired_<sid>）。
#   损坏安全侧（AC-2.8）：快照缺失/某卡行缺失/阶段号非数字/col3损坏 → 视同无基线，本轮该卡不触发任何
#   建议/报警、仅重建快照——不得把损坏值当 0 或 ≤2（否则与当前 ≥3 构成虚假跨越 → 误注入）。
_seg_threshold_default() { case "$1" in 2to3) printf '160000' ;; 6to7) printf '200000' ;; *) printf '' ;; esac; }
_seg_threshold_env() {
  # $1=边界；返回该边界阈值（env 覆写 · 非数字回退默认）
  local b="$1" v def
  def="$(_seg_threshold_default "$b")"
  case "$b" in
    2to3) v="${HARNESS_SEGMENT_T2:-}" ;;
    6to7) v="${HARNESS_SEGMENT_T6:-}" ;;
    *) printf '%s' "$def"; return 0 ;;
  esac
  case "$v" in ''|*[!0-9]*) printf '%s' "$def" ;; *) printf '%s' "$v" ;; esac
}

# 门族行匹配正则复刻（与 pretool_summary_flip_guard.sh FLIP_RE_1/3/5 同族 · AC-2.1 第3列 / AC-3.1 信号①）。
# 复刻而非共享 source：两 hook 无共享 source 层，此为 UserPromptSubmit 读盘侧独立副本（改门族正则须两处同步）。
UPI_FLIP_RE_1='\|[[:space:]]*1[[:space:]]+[^|]*\|[[:space:]]*PASSED([[:space:]]|\|)'
UPI_FLIP_RE_3='\|[[:space:]]*3[[:space:]]+[^|]*\|[[:space:]]*PASSED([[:space:]]|\|)'
UPI_FLIP_RE_5='\|[[:space:]]*5[[:space:]]+[^|]*\|[[:space:]]*PASSED([[:space:]]|\|)'

_upi_item_stage() {
  # 复用 emit_main_list 同一口径从 brief item 提取阶段号（AC-2.1 · 单源消除双解析漂移 · 与 L371 同 sed 式）
  printf '%s' "$1" | sed -n 's/.*阶段 \([0-9][0-9]*\).*/\1/p'
}
_upi_item_card() {
  # 从 brief item 提取卡目录名（首个 ` · ` 之前 · = list_flows A_name / 目录 basename）
  local it="$1"; printf '%s' "${it%% · *}"
}
_upi_phase_passed_file() {
  # $1=summary文件 $2=阶段(1/3/5)；文件内命中该阶段 PASSED 行返回 0（门族行匹配 · AC-2.1/AC-3.1 信号①）
  local f="$1" ph="$2" re
  case "$ph" in
    1) re="$UPI_FLIP_RE_1" ;;
    3) re="$UPI_FLIP_RE_3" ;;
    5) re="$UPI_FLIP_RE_5" ;;
    *) return 1 ;;
  esac
  [ -r "$f" ] || return 1
  grep -qE "$re" "$f" 2>/dev/null
}
_upi_passed_set_csv() {
  # $1=summary文件；输出已 PASSED 的 1/3/5 阶段集 csv（如 "1,3"；空则空串）
  local f="$1" ph out=""
  for ph in 1 3 5; do
    if _upi_phase_passed_file "$f" "$ph"; then out="${out:+$out,}$ph"; fi
  done
  printf '%s' "$out"
}
_upi_csv_has() {
  # $1=csv 集 $2=元素；集内含该元素返回 0
  case ",${1}," in *",${2},"*) return 0 ;; *) return 1 ;; esac
}
_upi_col3_valid() {
  # col3 合法性（AC-2.8）：空 或 元素∈{1,3,5} 逗号分隔（形如 1 / 1,3 / 1,3,5）；损坏 → 视同无基线
  case "$1" in
    '') return 0 ;;
    *[!135,]*) return 1 ;;
    *) return 0 ;;
  esac
}

_upi_active_brief() {
  # $1=root；取 --active --format=brief（复用 emit_main_list 同链定位 _locate_script）；失败/缺失返回 1
  local root="$1" lf brief
  lf="$(_locate_script list_flows.sh "$root" || true)"
  [ -n "$lf" ] && [ -f "$lf" ] || return 1
  brief="$(bash "$lf" --active --format=brief 2>/dev/null)" || return 1
  printf '%s' "$brief"
}

_seg_maybe_suggest() {
  # $1=card $2=old_stage(数字) $3=new_stage(数字) $4=wsum(数字) $5=keyfile
  # 边界判定 + 水位阈值 + 去重 → 注入分段建议（文案/阈值 env 覆写/去重语义与退役前 emit_segment_suggest 一致）
  local card="$1" olds="$2" news="$3" wsum="$4" kf="$5" boundary="" thr key wk stage_label
  if [ "$olds" -le 2 ] && [ "$news" -ge 3 ]; then
    boundary="2to3"
  elif [ "$olds" -le 6 ] && [ "$news" -ge 7 ]; then
    boundary="6to7"
  else
    return 0
  fi
  thr="$(_seg_threshold_env "$boundary")"
  case "$thr" in ''|*[!0-9]*) return 0 ;; esac
  [ "$wsum" -ge "$thr" ] || return 0                  # 水位未达阈值 → 不建议
  # 单次去重（AC-2.4 · 卡+边界 · 多卡各自隔离 · keyfile 一键一行）
  key="${card}|${boundary}"
  if [ -r "$kf" ] && grep -qxF "$key" "$kf" 2>/dev/null; then return 0; fi
  printf '%s\n' "$key" >> "$kf" 2>/dev/null || true
  wk=$(( wsum / 1000 ))
  case "$boundary" in 2to3) stage_label="阶段2→3（HITL-2 决议后）" ;; 6to7) stage_label="阶段6→7（阶段6 闭合后）" ;; esac
  printf '\n'
  printf '%s\n' "  ✂️ [harness:segment_suggest] 分段建议（旁路·可无视）：当前上下文水位≈${wk}k 已达阈值 $(( thr / 1000 ))k，且本会话刚跨越 ${stage_label} 边界（卡 ${card}）。"
  printf '%s\n' "     建议在此阶段边界分段续跑（/clear 同窗优先于新窗口，二者均优于 /compact）以省主循环缓存成本——见开发流程规范 DF-017。"
  printf '%s\n' "     采纳则 Owner 先写交接哨兵（source lib 后 \`harness_write_segment_handoff \"${card}\" \"<下一步阶段>\" \"<一句交接注>\"\`），/clear 后新会话按启动序列自动续推该卡；注意授权台账按 sid 隔离，切前授权失效需切后重授。"
}

_t4_maybe_alarm() {
  # $1=card $2=cur_set(当前PASSED的1/3/5 csv) $3=old_set(基线PASSED csv) $4=deleg台账
  # T-3 双信号（AC-3.1）：①当前阶段行 PASSED（cur_set 内）②不在基线第3列（本会话内翻牌 · 覆盖 sed 只翻表行
  #   不移动阶段头字段的部分翻牌）。双信号成立 ∧ 台账可读 ∧ 无同卡 generator 记录 → 报警（只曝光不 deny）。
  local card="$1" cur="$2" old="$3" deleg="$4" ph newly=""
  for ph in 1 3 5; do
    if _upi_csv_has "$cur" "$ph" && ! _upi_csv_has "$old" "$ph"; then
      newly="${newly:+$newly,}$ph"
    fi
  done
  [ -n "$newly" ] || return 0                         # 无本会话内新翻牌 → 不报警（AC-3.2 跨会话既有 PASSED 不误报）
  # 台账缺失/不可读 → fail-open 不报警（AC-3.4）；可读且有同卡 generator 记录 → 不报警（AC-3.3）；无记录 → 报警（AC-3.1）
  [ -r "$deleg" ] || return 0
  if awk -F'\t' -v c="$card" '($2 ~ /generator/) && ($4 == c){f=1} END{exit f?0:1}' "$deleg" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "  ⚠️ [harness:t4_reconcile] 事后对账（软兜底·只曝光不阻断）：卡 ${card} 阶段 ${newly} 本会话内翻 PASSED，但委派台账无同卡 generator 记录（疑似绕过 T4 翻牌门 / Owner inline 逃逸）。建议：经 Agent 委派 generator 补出该阶段产出与证据后再续推（DF-015）。"
}

emit_stage_reconcile() {
  # $1=water_sum(原始token·空=水位不可得) $2=state_dir $3=sid $4=changes_dir $5=root
  # T-2 分段建议（读盘快照差分）+ T-3 T4 事后对账报警（双信号）；旁路 · 任何失败均不改主注入退出码（AC-2.7/AC-3.4）。
  local wsum="$1" sdir="$2" sid="$3" changes_dir="$4" root="$5"
  local snapf="$sdir/last_seen_stage_${sid}.log" kf="$sdir/segment_suggest_fired_${sid}"
  local deleg="$sdir/delegations_${sid}.log"
  local brief old_snap new_snap="" line item one card stage sumf cur_set old_line old_stage old_set baseline_ok

  brief="$(_upi_active_brief "$root" || true)"
  # brief 不可得（list_flows 缺/失败）或无活跃卡 → 保留旧快照基线、跳过本轮对账（AC-2.7 fail-open）
  [ -n "$brief" ] || return 0
  # 先读旧快照全文入变量（AC-2.1 读写次序：先读后写；后续比对只读此变量，绝不读正在写的文件）
  old_snap="$(cat "$snapf" 2>/dev/null || true)"

  # 遍历活跃 ten-stage 卡（brief 行 `ten-stage[STATE]: item / item`；--active 已排除 PASSED 卡）
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in ten-stage\[*) ;; *) continue ;; esac
    item="${line#*]: }"
    while IFS= read -r one; do
      [ -z "$one" ] && continue
      card="$(_upi_item_card "$one")"
      stage="$(_upi_item_stage "$one")"
      [ -n "$card" ] || continue
      case "$stage" in ''|*[!0-9]*) stage="" ;; esac      # 当前阶段号非数字 → 记空（不参与边界差分）
      sumf="$changes_dir/$card/summary.md"
      cur_set="$(_upi_passed_set_csv "$sumf")"

      # 取该卡旧快照行（从已读入变量 · 不触盘）；AC-2.8 损坏安全侧：col2 须数字、col3 须合法集，否则视同无基线
      old_line="$(printf '%s\n' "$old_snap" | awk -F'\t' -v c="$card" '$1==c{print; exit}' 2>/dev/null || true)"
      old_stage=""; old_set=""; baseline_ok=0
      if [ -n "$old_line" ]; then
        old_stage="$(printf '%s' "$old_line" | awk -F'\t' '{print $2}')"
        old_set="$(printf '%s' "$old_line" | awk -F'\t' '{print $3}')"
        case "$old_stage" in ''|*[!0-9]*) old_stage="" ;; esac
        if [ -n "$old_stage" ] && _upi_col3_valid "$old_set"; then baseline_ok=1; fi
      fi

      # T-3 事后对账报警（先曝光 · 双信号 · 仅有效基线；无基线=首轮不报警 AC-3.2）
      if [ "$baseline_ok" = "1" ]; then
        _t4_maybe_alarm "$card" "$cur_set" "$old_set" "$deleg"
      fi
      # T-2 边界跨越（仅有效基线 + 当前阶段号可用 + 水位可得 · AC-2.7 水位不可得不建议）
      if [ "$baseline_ok" = "1" ] && [ -n "$stage" ] && [ -n "$wsum" ]; then
        case "$wsum" in ''|*[!0-9]*) : ;; *) _seg_maybe_suggest "$card" "$old_stage" "$stage" "$wsum" "$kf" ;; esac
      fi

      # 累积新快照行（AC-2.1 冻结三列 schema · 真实 TAB 分隔）
      new_snap="${new_snap}${card}"$'\t'"${stage}"$'\t'"${cur_set}"$'\n'
    done < <(printf '%s\n' "$item" | awk '{gsub(/ \/ /, "\n"); print}')
  done <<< "$brief"

  # 后覆盖写新快照（AC-2.1 读写次序：写在所有比对之后 · 写失败静默 fail-open）
  mkdir -p "$sdir" 2>/dev/null || return 0
  [ -f "$sdir/.gitignore" ] || printf '*\n' > "$sdir/.gitignore" 2>/dev/null || true
  printf '%s' "$new_snap" > "$snapf" 2>/dev/null || true
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
  # STATE_DIR 根走 harness_state_root()（方案甲 · 会话内稳定 · feat-segmentation-and-statedir-fix T-B）——
  # 与 pre_bash_guard / summary_flip_guard 读端同口径，worktree 会话读写落同一目录（AC-B）。
  # 注意：changes_dir 仍用 root=resolve_root()（内容定位·跟 cwd 是其应然），只统一 STATE_DIR 解析。
  local _state_root _state_dir _sid="nosid" _upi_sid _sentinel _contract_missing=0
  _state_root="$(harness_state_root)"
  _state_dir="${HARNESS_STATE_DIR:-$_state_root/.harness/state}"
  if [ -n "$stdin_raw" ]; then
    _upi_sid="$(printf '%s' "$stdin_raw" | tr -d '\n\r' \
      | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 \
      | sed -E 's/^"session_id"[[:space:]]*:[[:space:]]*"//; s/"$//')"
    [ -n "$_upi_sid" ] && _sid="$(printf '%s' "$_upi_sid" | tr -cd 'A-Za-z0-9._-')"
  fi
  _sentinel="$_state_dir/.resident_contract_injected_${_sid}"
  [ -f "$_sentinel" ] || _contract_missing=1

  # T1 用户授权台账落盘（feat-hitl-authz-hardening · AC-1）——置于 g1 让位之后、仅主注入副本落盘，
  # 避免双活场景 append-only 审计文件双写（与常驻契约哨兵同口径）。fail-open 恒不影响注入。
  append_user_prompt_ledger "$stdin_raw" "$_state_dir" "$_sid" || true

  # 上下文水位（T-A1）：transcript_path 自 UserPromptSubmit stdin payload 取（官方 hook 公共字段）；
  # 水位 = 最后 assistant usage(cache_read+cache_creation)。fail-open：任一环节缺 → _water 留空、水位行静默跳过。
  local _tp="" _water=""
  if [ -n "$stdin_raw" ] && command -v jq >/dev/null 2>&1; then
    _tp="$(printf '%s' "$stdin_raw" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  fi
  [ -n "$_tp" ] && _water="$(compute_water_sum "$_tp" || true)"

  emit_header
  printf '%s\n' "  仓库根：$root"
  if [ -n "$_water" ]; then
    printf '  上下文水位≈%sk\n' "$(( _water / 1000 ))"
  fi
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
  # 分段建议（T-2）+ T4 事后对账报警（T-3）· 读盘快照差分对账 · 旁路 · 恒 exit 0
  # （chore-hook-governance-hardening-20260715 · 退役寄生记号 stage_progress，改快照 last_seen_stage）
  emit_stage_reconcile "$_water" "$_state_dir" "$_sid" "$changes_dir" "$root"
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
