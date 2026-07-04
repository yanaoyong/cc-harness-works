#!/usr/bin/env bash
# ============================================================================
# acceptance-run.sh — 验收回填 pre/post 执行器（acceptance-backfill 组件）
#
# 用法:
#   acceptance-run.sh <pre|post> <套件根> <CASE-ID> [--dry-run]
#     pre|post   提取并执行 case 回填模板的【运行前】/【运行后】首个 ```bash 块
#     套件根     .harness/acceptance/ 下套件目录；相对仓库根或绝对路径均可
#     CASE-ID    如 RP-09 / FS-05（按 cases/<ID>.md 或 cases/<ID>-*.md 定位）
#     --dry-run  只定位/提取不执行、零写入（供守护测试全集可解析断言）
#
# 退出码: 0 成功（含占位豁免）/ 1 断言性失败（锚缺失或块内命令失败）
#         2 参数错误 / 5 内部错误
# 纪律:   stdout 只输出一行结构化 JSON 摘要；诊断与块输出走 stderr。
#         只写 <套件根>/results/.evidence/**（不存在则创建）；绝不写 cases/。
#
# 实现取舍注记（spec R2 要求注明）:
#  - 标题锚归一化容差（M-3）: 标题行去空白（含全角空格）与全/半角中点（·/.）及
#    【】括号后，按 `运行前|运行后` 前缀识别——兼容「## 【运行前 · 前置验证 / 造条件】」
#    「### 运行前 · 前置 / 造条件」「### 运行前·前置/造条件」等存量变体。
#    锚要求 >=2 个 '#'（##/###，与存量三段式模板一致），避免 bash 注释行
#    （单个 # 开头）被误判为节边界/锚。权威容差规则见 rule《验收回填与证据捕获规范》§1。
#  - env 状态传递选「set -a 子 shell + 执行前后 env 差分」而非「按行扫描块文本赋值」:
#    块内赋值常含 $(mktemp ...) 等运行时求值，扫描文本只能拿字面量、post 再 source
#    会重新求值生成新路径（错值）；env 差分（LC_ALL=C sort + comm -13）拿到实际值，
#    简单且确定。局限: 多行值破坏 KEY=VALUE 行式（存量块无此形态，过滤掉续行）。
#  - 占位语义（M-1）: 节标题可定位但节内无 ```bash 围栏块（如 FS-06~14/17/18 的
#    无标注占位符）→ exit 0 + 写 <mode>-skipped.note 显式豁免留痕；不臆造命令、
#    不把占位文本当命令执行。
#  - 围栏配对: 开栏记录反引号数 N，只有 >=N 个反引号的纯围栏行才闭合（外层 ````markdown
#    模板围栏内嵌 ```bash 的存量形态因此可正确提取）。
# ============================================================================

set -euo pipefail
# 局部放宽点仅一处：执行块的管道段临时 set +e（需拿块退出码且日志必须完整留档）。

die() { # $1=退出码 其余=stderr 诊断
  local code="$1"; shift
  echo "acceptance-run: $*" >&2
  exit "$code"
}

# ---------- 参数解析 ----------
MODE="" SUITE_ARG="" CASE_ID="" DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -*) die 2 "未知选项: $arg（用法: acceptance-run.sh <pre|post> <套件根> <CASE-ID> [--dry-run]）" ;;
    *)
      if [ -z "$MODE" ]; then MODE="$arg"
      elif [ -z "$SUITE_ARG" ]; then SUITE_ARG="$arg"
      elif [ -z "$CASE_ID" ]; then CASE_ID="$arg"
      else die 2 "多余参数: $arg"
      fi ;;
  esac
done
[ -n "$MODE" ] && [ -n "$SUITE_ARG" ] && [ -n "$CASE_ID" ] \
  || die 2 "缺少参数（用法: acceptance-run.sh <pre|post> <套件根> <CASE-ID> [--dry-run]）"
case "$MODE" in pre|post) ;; *) die 2 "模式须为 pre|post，收到: $MODE" ;; esac

# ---------- 路径推导（零硬编码: 仓库根一律 git 推导） ----------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die 5 "无法定位仓库根（git rev-parse --show-toplevel 失败，请在仓库内运行）"
case "$SUITE_ARG" in
  /*) SUITE_ROOT="$SUITE_ARG" ;;
  *)  SUITE_ROOT="$REPO_ROOT/$SUITE_ARG" ;;
esac
[ -d "$SUITE_ROOT" ] || die 2 "套件根不存在: $SUITE_ROOT"
[ -d "$SUITE_ROOT/cases" ] || die 2 "套件根下无 cases/ 目录: $SUITE_ROOT"

# case 文件定位: 先精确 <ID>.md，再 <ID>-*.md（防 RP-1 误匹配 RP-10）
CASE_FILE="" MATCHES=""
for f in "$SUITE_ROOT/cases/$CASE_ID.md" "$SUITE_ROOT/cases/$CASE_ID"-*.md; do
  [ -f "$f" ] || continue
  MATCHES="$MATCHES$f"$'\n'
  [ -z "$CASE_FILE" ] && CASE_FILE="$f"
done
[ -n "$CASE_FILE" ] || die 2 "找不到 case 文件: $SUITE_ROOT/cases/$CASE_ID[-.]*.md"
if [ "$(printf '%s' "$MATCHES" | grep -c .)" -gt 1 ]; then
  printf '%s' "$MATCHES" >&2
  die 2 "CASE-ID '$CASE_ID' 匹配到多个 case 文件（见上），请用更精确的 ID"
fi

if [ "$MODE" = "pre" ]; then ANCHOR="运行前"; else ANCHOR="运行后"; fi

# ---------- 临时文件 ----------
TMP_BLOCK="$(mktemp "${TMPDIR:-/tmp}/acc-run-block.XXXXXX")" || die 5 "mktemp 失败"
TMP_WRAP="$(mktemp "${TMPDIR:-/tmp}/acc-run-wrap.XXXXXX")"   || die 5 "mktemp 失败"
TMP_ENV_BEFORE="$(mktemp "${TMPDIR:-/tmp}/acc-run-envb.XXXXXX")" || die 5 "mktemp 失败"
TMP_ENV_AFTER="$(mktemp "${TMPDIR:-/tmp}/acc-run-enva.XXXXXX")"  || die 5 "mktemp 失败"
trap 'rm -f "$TMP_BLOCK" "$TMP_WRAP" "$TMP_ENV_BEFORE" "$TMP_ENV_AFTER"' EXIT

# ---------- 块提取（awk 单趟状态机；macOS bash3.2/BSD awk 兼容，不用 bash4+ 特性） ----------
# 状态: 0=找锚 1=节内找 ```bash 2=捕获块内容 3=跳过非 bash 围栏块
# 节边界: 节内（非围栏中）遇到任意 ##+ 标题即节结束（含下一个三段式锚）。
STATUS="$(awk -v target="$ANCHOR" -v out="$TMP_BLOCK" '
  function is_heading(l) { sub(/^[ \t]*/, "", l); return (l ~ /^##/) }
  function norm(l) {
    gsub(/[# \t]/, "", l)
    gsub(/【|】|·|\.|　/, "", l)   # 去 #、空白（含全角）、全/半角中点、【】
    return l
  }
  BEGIN { st = 0; flen = 0; anchored = 0; found = 0 }
  {
    if (st == 0) {
      if (is_heading($0) && index(norm($0), target) == 1) { st = 1; anchored = 1 }
      next
    }
    if (st == 1) {
      t = $0; sub(/^[ \t]*/, "", t)
      if (match(t, /^```+/)) {
        flen = RLENGTH; rest = substr(t, RLENGTH + 1); gsub(/[ \t]/, "", rest)
        if (rest == "bash") st = 2; else st = 3
        next
      }
      if (is_heading($0)) exit   # 节结束仍未见 bash 块
      next
    }
    # st==2/3: 围栏内。只有 >= 开栏反引号数的纯围栏行才闭合。
    t = $0; sub(/^[ \t]*/, "", t)
    if (match(t, /^```+/) && RLENGTH >= flen) {
      rest = substr(t, RLENGTH + 1); gsub(/[ \t]/, "", rest)
      if (rest == "") {
        if (st == 2) { found = 1; exit }
        st = 1; next
      }
    }
    if (st == 2) print $0 > out
    next
  }
  END { if (!anchored) print "NOANCHOR"; else if (found) print "FOUND"; else print "NOBLOCK" }
' "$CASE_FILE")" || die 5 "awk 提取失败: $CASE_FILE"

emit_json() { # $1=status $2=log(可空→null) $3=脚本退出码
  local log_json="null"
  [ -n "$2" ] && log_json="\"$2\""
  printf '{"tool":"acceptance-run","mode":"%s","case":"%s","case_file":"%s","status":"%s","log":%s,"exit":%s}\n' \
    "$MODE" "$CASE_ID" "$CASE_FILE" "$1" "$log_json" "$3"
}

# ---------- 锚缺失: 断言性失败 ----------
if [ "$STATUS" = "NOANCHOR" ]; then
  echo "acceptance-run: 【${ANCHOR}】标题锚定位失败: $CASE_FILE（归一化容差下仍无 ##+ 标题以「${ANCHOR}」开头；核对 case 是否含三段式回填模板）" >&2
  emit_json "anchor-missing" "" 1
  exit 1
fi

# ---------- dry-run: 只报定位结果，零写入 ----------
if [ "$DRY_RUN" -eq 1 ]; then
  if [ "$STATUS" = "FOUND" ]; then
    echo "acceptance-run(dry-run): 【${ANCHOR}】bash 块已定位（$(wc -l < "$TMP_BLOCK" | tr -d ' ') 行），未执行" >&2
    emit_json "located-executable" "" 0
  else
    echo "acceptance-run(dry-run): 【${ANCHOR}】节可定位但无 \`\`\`bash 块（占位符），未执行" >&2
    emit_json "located-placeholder" "" 0
  fi
  exit 0
fi

# ---------- 证据目录（唯一写入面: results/.evidence/**） ----------
EVID_DIR="$SUITE_ROOT/results/.evidence/$CASE_ID"
mkdir -p "$EVID_DIR" || die 5 "无法创建证据目录: $EVID_DIR"
ENV_FILE="$EVID_DIR/env"
NOW_HUMAN="$(date '+%Y-%m-%d %H:%M:%S %z')"

# ---------- 占位豁免（M-1: 可定位≠可执行） ----------
if [ "$STATUS" = "NOBLOCK" ]; then
  NOTE_FILE="$EVID_DIR/${MODE}-skipped.note"
  {
    echo "reason: 占位符无可执行块——【${ANCHOR}】节标题可定位，但节内无 \`\`\`bash 围栏块（不臆造命令、不把占位文本当命令执行）"
    echo "case_file: $CASE_FILE"
    echo "mode: $MODE"
    echo "time: $NOW_HUMAN"
  } > "$NOTE_FILE"
  echo "acceptance-run: 占位豁免——【${ANCHOR}】节无可执行 bash 块，已留痕 $NOTE_FILE；请按案例正文人工准备该段" >&2
  emit_json "placeholder-skipped" "" 0
  exit 0
fi

# ---------- 执行（FOUND） ----------
# 执行 cwd = 套件根所在仓库根（套件可能位于 /tmp fixture 仓）；块内自带 cd。
EXEC_ROOT="$(git -C "$SUITE_ROOT" rev-parse --show-toplevel 2>/dev/null)" || EXEC_ROOT="$SUITE_ROOT"
TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$EVID_DIR/${MODE}-${TS}.log"

{
  echo "#!/usr/bin/env bash"
  echo "set -o pipefail"
  printf 'cd %q || exit 1\n' "$EXEC_ROOT"
  if [ "$MODE" = "post" ] && [ -f "$ENV_FILE" ]; then
    # post: 先 source pre 留下的 env 状态文件（fixture 路径等）
    printf 'set -a; . %q; set +a\n' "$ENV_FILE"
  fi
  if [ "$MODE" = "pre" ]; then
    printf 'env | LC_ALL=C sort > %q\n' "$TMP_ENV_BEFORE"
  fi
  echo "set -a"   # 块内顶层赋值自动导出 → env 差分可见
  echo "set -e"   # 块内未被自行处理的非零命令 = 断言性失败
  cat "$TMP_BLOCK"
  echo ""
  echo "set +e; set +a"
  if [ "$MODE" = "pre" ]; then
    printf 'env | LC_ALL=C sort > %q\n' "$TMP_ENV_AFTER"
  fi
  echo "exit 0"
} > "$TMP_WRAP"

{
  echo "# acceptance-run 留档"
  echo "case_file: $CASE_FILE"
  echo "mode: $MODE"
  echo "start: $NOW_HUMAN"
  echo "exec_cwd: $EXEC_ROOT"
  echo "---"
} > "$LOG_FILE"

# 块输出合流 tee 到日志 + 本进程 stderr（stdout 保持 JSON-only）。
set +e   # 放宽理由: 需拿到块退出码继续留档，而非让 -e 直接终止本脚本
bash "$TMP_WRAP" 2>&1 | tee -a "$LOG_FILE" >&2
RC="${PIPESTATUS[0]}"
set -e

{
  echo "---"
  echo "exit_code: $RC"
} >> "$LOG_FILE"

# pre 成功 → env 差分写状态文件（供 post source）；失败不写。
if [ "$MODE" = "pre" ] && [ "$RC" -eq 0 ]; then
  comm -13 "$TMP_ENV_BEFORE" "$TMP_ENV_AFTER" \
    | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' \
    | grep -Ev '^(_|SHLVL|PWD|OLDPWD)=' > "$ENV_FILE" || true   # 无新变量 → 空 env 文件
fi

if [ "$RC" -eq 0 ]; then
  emit_json "executed" "$LOG_FILE" 0
  exit 0
fi
echo "acceptance-run: 【${ANCHOR}】块内命令非零退出（rc=$RC），日志已完整留档: $LOG_FILE" >&2
emit_json "block-failed" "$LOG_FILE" 1
exit 1
