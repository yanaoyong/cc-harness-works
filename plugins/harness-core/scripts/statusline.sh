#!/usr/bin/env bash
# Claude Code statusLine
# 显示段序：模型 | 上下文(已用 tokens + 占比%) | git 短哈希 | 项目目录(📁) | Harness 流程状态(⛓) | 工作目录(📂)
# 输入：Claude Code 通过 stdin 传入会话 JSON。输出：单行文本（支持 ANSI 颜色）。
# 基线说明（TG-3 · 评审 LOW-2）：statusline 保持 `set -o pipefail`，**本轮不新增 `-u`**——
# 本脚本跨 ANSI/awk/git 多分支变量繁多，无法逐一确证 `-u` 下零未定义引用（误加 -u = 每次渲染
# 即崩/空行的真实回归源 · R3 未覆盖 -u）；故采保守路径，`-u` 留作独立评估。明确不加 `-e`（同 hook 容错纪律）。
set -o pipefail

input="$(cat)"

# ---- python3 缺失降级（AC-3.1）：本脚本 JSON 解析与 truncate_cp 硬依赖 python3；
#      缺 python3 → 退化为最小可用状态行（仅 git 短哈希 + 工作目录名 · 不解析 JSON），exit 0，不崩不刷错。----
if ! command -v python3 >/dev/null 2>&1; then
  dg_cwd="${PWD##*/}"; [ -n "$dg_cwd" ] || dg_cwd="/"
  dg_git=""
  if dg_sha="$(git rev-parse --short HEAD 2>/dev/null)" && [ -n "$dg_sha" ]; then
    dg_git=" | ⎇ ${dg_sha}"
  fi
  printf 'harness%s | 📂 %s\n' "$dg_git" "$dg_cwd"
  exit 0
fi

# ---- 用 python3 解析 JSON + 读 transcript 算上下文 tokens（单行 TSV 输出）----
fields="$(printf '%s' "$input" | python3 -c '
import sys, json, os
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}

model = d.get("model") or {}
mid   = model.get("id", "") or ""
mname = model.get("display_name", "") or mid
ws    = d.get("workspace") or {}
cwd   = d.get("cwd", "") or ws.get("current_dir", "") or ""
pdir  = ws.get("project_dir", "") or cwd
tr    = d.get("transcript_path", "") or ""

# 本会话花费(美元) + 改动行数：直接取 Claude Code 注入的 cost 块（缺则 0）
cost     = d.get("cost") or {}
cost_usd = cost.get("total_cost_usd", 0) or 0
ladd     = cost.get("total_lines_added", 0) or 0
lrem     = cost.get("total_lines_removed", 0) or 0

# 上下文总量：模型 id 含 1m → 100 万，否则 20 万
low = mid.lower()
total = 1000000 if ("1m" in low) else 200000

# 已用上下文：transcript 中最近一条「主线（非子 agent）」消息的 usage
used = 0
if tr and os.path.exists(tr):
    last = None
    try:
        with open(tr, encoding="utf-8") as f:
            for line in f:
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                if e.get("isSidechain"):          # 跳过子 agent 自己的上下文
                    continue
                msg = e.get("message")
                if isinstance(msg, dict) and isinstance(msg.get("usage"), dict):
                    last = msg["usage"]
    except Exception:
        last = None
    if last:
        used = (last.get("input_tokens", 0) or 0) \
             + (last.get("cache_read_input_tokens", 0) or 0) \
             + (last.get("cache_creation_input_tokens", 0) or 0)

print("\x1f".join([mid, mname, cwd, pdir, str(used), str(total),
                   "%.2f" % float(cost_usd), str(int(ladd)), str(int(lrem))]))
')"

# 用 \x1f（单元分隔符）而非 tab：tab 属 IFS 空白会折叠空字段，\x1f 可保留空字段
IFS=$'\x1f' read -r MODEL_ID MODEL_NAME CWD PROJECT_DIR CTX_USED CTX_TOTAL COST_USD LINES_ADDED LINES_REMOVED <<< "$fields"
[ -n "$MODEL_NAME" ] || MODEL_NAME="$MODEL_ID"
[ -n "$MODEL_NAME" ] || MODEL_NAME="?"
[ -n "$CWD" ] || CWD="$PWD"
[ -n "$PROJECT_DIR" ] || PROJECT_DIR="$CWD"
[ -n "$CTX_USED" ] || CTX_USED=0
[ -n "$CTX_TOTAL" ] || CTX_TOTAL=200000
[ -n "$COST_USD" ] || COST_USD="0.00"
[ -n "$LINES_ADDED" ] || LINES_ADDED=0
[ -n "$LINES_REMOVED" ] || LINES_REMOVED=0

# ---- 截断阈值（Unicode 码点计数，单位=码点数；省略号 … 计 1 码点）----
HARNESS_MAXLEN=34   # Harness 流程状态段最大码点数（超长→保留尾部/阶段后缀 + 前置 …）

# 共用截断辅助：按 Unicode 码点截断（禁用 bash ${#var} 避免 locale 字节计数漂移）
# $1=待截断串  $2=最大码点数  $3=head（保首/省略号置尾）|tail（保尾/省略号置首）
truncate_cp() {
  python3 -c 'import sys
s=sys.argv[1]; m=int(sys.argv[2]); d=sys.argv[3]
if len(s)<=m: sys.stdout.write(s)
elif d=="head": sys.stdout.write(s[:m-1]+"…")
else: sys.stdout.write("…"+s[-(m-1):])' "$1" "$2" "$3"
}

# ---- 颜色（ANSI）----
RESET=$'\033[0m'; DIM=$'\033[2m'; SEP="${DIM} | ${RESET}"
C_MODEL=$'\033[36m'    # cyan
C_DIR=$'\033[34m'      # blue
C_CWD=$'\033[2m'       # dim
C_GIT=$'\033[35m'      # magenta
C_HARNESS=$'\033[33m'  # yellow
C_COST=$'\033[32m'     # green（花费）
C_LINES=$'\033[36m'    # cyan（改动行数）

# ---- 目录显示（项目目录段已移除；PROJECT_DIR 仍用于计算工作目录的相对子路径）----
# 当前目录：项目子目录时显示相对子路径（如 .harness/scripts），否则显示当前目录名
if [ -n "$PROJECT_DIR" ] && [ "$CWD" != "$PROJECT_DIR" ] && [ "${CWD#$PROJECT_DIR/}" != "$CWD" ]; then
  CWD_DISP="${CWD#$PROJECT_DIR/}"
else
  CWD_DISP="${CWD##*/}"
fi
[ -n "$CWD_DISP" ] || CWD_DISP="/"

# ---- 上下文 tokens 人类可读 + 百分比 ----
CTX_HUMAN="$(awk -v u="$CTX_USED" 'BEGIN{ if (u>=1000) printf "%.1fk", u/1000; else printf "%d", u }')"
if [ "$CTX_TOTAL" -gt 0 ] 2>/dev/null; then
  CTX_PCT="$(awk -v u="$CTX_USED" -v t="$CTX_TOTAL" 'BEGIN{ printf "%.0f", u*100/t }')"
else
  CTX_PCT="0"
fi
# 占比颜色：<50 绿 / <80 黄 / >=80 红
if   [ "$CTX_PCT" -ge 80 ] 2>/dev/null; then C_CTX=$'\033[31m'   # red
elif [ "$CTX_PCT" -ge 50 ] 2>/dev/null; then C_CTX=$'\033[33m'   # yellow
else C_CTX=$'\033[32m'; fi                                       # green

# ---- git 短哈希 ----
# 注意：禁用全量 git status（会扫描 .claude/worktrees 等大量 untracked 内容而挂死）；
# 脏标记只看「已跟踪文件的改动」（git diff），快且安全。所有 git 调用加 timeout 兜底。
GIT_SEG=""
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 2"
if SHA="$($TO git -C "$CWD" rev-parse --short HEAD 2>/dev/null)" && [ -n "$SHA" ]; then
  DIRTY=""
  if ! $TO git -C "$CWD" diff --quiet 2>/dev/null || ! $TO git -C "$CWD" diff --cached --quiet 2>/dev/null; then
    DIRTY="*"
  fi
  GIT_SEG="${SEP}${C_GIT}⎇ ${SHA}${DIRTY}${RESET}"
fi

# ---- Harness 流程状态（复用 list_flows.sh --active --format=brief）----
HARNESS_SEG=""
LF="$PROJECT_DIR/.harness/scripts/list_flows.sh"
if [ -f "$LF" ]; then
  if command -v timeout >/dev/null 2>&1; then
    ACTIVE="$(cd "$PROJECT_DIR" && timeout 3 bash "$LF" --active --format=brief 2>/dev/null | head -1)"
  else
    ACTIVE="$(cd "$PROJECT_DIR" && bash "$LF" --active --format=brief 2>/dev/null | head -1)"
  fi
  if [ -z "$ACTIVE" ]; then
    HARNESS_DISP="空闲"
  else
    # 形如 "ten-stage[IN_PROGRESS]: feat-xxx-20260602 · 阶段3 / feat-yyy · ..."
    # 精简：去组前缀/状态词、选热卡，去掉日期后缀，多于一张追加 +N
    BODY="$(printf '%s' "$ACTIVE" | sed -E 's/^[a-z-]+\[//; s/\]: / /')"
    REST="${BODY#* }"
    FIRST="${REST%% / *}"
    EXTRA=""
    if [ "$REST" != "$FIRST" ]; then
      N="$(printf '%s' "$REST" | awk -F ' / ' '{print NF-1}')"
      EXTRA=" +${N}"
      # brief 为目录扫描序（字母序），首卡未必是正在推进的卡；
      # 按各卡 summary.md mtime 选最近变动者显示（mtime 不可得计 -1；全部不可得回退首卡）
      BEST=""; BEST_MT=-1
      REM="$REST"
      while [ -n "$REM" ]; do
        ITEM="${REM%% / *}"
        if [ "$ITEM" = "$REM" ]; then REM=""; else REM="${REM#* / }"; fi
        CARD="${ITEM%% · *}"
        MT="$(stat -c %Y "$PROJECT_DIR/.harness/changes/$CARD/summary.md" 2>/dev/null \
           || stat -f %m "$PROJECT_DIR/.harness/changes/$CARD/summary.md" 2>/dev/null \
           || echo -1)"
        if [ "$MT" -gt "$BEST_MT" ] 2>/dev/null; then BEST_MT="$MT"; BEST="$ITEM"; fi
      done
      [ -n "$BEST" ] && FIRST="$BEST"
    fi
    # 去掉卡名里的 -YYYYMMDD 日期后缀，' · ' 收成空格
    FIRST="$(printf '%s' "$FIRST" | sed -E 's/-[0-9]{8}//; s/ · / /')"
    HARNESS_DISP="${FIRST}${EXTRA}"
  fi
  # Harness 段截断：尾部保留 + 前置 …（阶段/状态后段最具即时信息量）
  HARNESS_DISP="$(truncate_cp "$HARNESS_DISP" "$HARNESS_MAXLEN" tail)"
  HARNESS_SEG="${SEP}${C_HARNESS}⛓ ${HARNESS_DISP}${RESET}"
fi

# ---- 花费 + 改动行数段（数据取自 Claude Code 注入的 cost 块 · 各自前置 SEP）----
COST_SEG="${SEP}${C_COST}💰 \$${COST_USD}${RESET}"
LINES_SEG="${SEP}${C_LINES}改动 +${LINES_ADDED}/−${LINES_REMOVED}${RESET}"

# ---- 组装单行 ----
# 段序：① 模型 → ② 上下文(已用+占比) → ③ git(⎇) → ④ 花费(💰) → ⑤ 改动行数 → ⑥ Harness(⛓) → ⑦ 工作目录(📂)
# 必现段（模型/上下文/花费/改动/工作目录）各自前置 SEP（模型为首段无前导 SEP）；
# 可选段（git/harness）把 SEP 嵌进自身、缺失则整段为空，避免悬空分隔符。
printf '%s%s%s%s%s (%s%%)%s%s%s%s%s%s📂 %s%s\n' \
  "$C_MODEL" "$MODEL_NAME" "$RESET" \
  "$SEP$C_CTX" "$CTX_HUMAN" "$CTX_PCT" "$RESET" \
  "$GIT_SEG" \
  "$COST_SEG" \
  "$LINES_SEG" \
  "$HARNESS_SEG" \
  "$SEP$C_CWD" "$CWD_DISP" "$RESET"
