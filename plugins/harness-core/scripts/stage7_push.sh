#!/usr/bin/env bash
# stage7_push.sh —— 阶段 7（代码推送）执行脚本（变更 feat-stage-exec-scripts-20260712 · T2）
#
# 定位：阶段 7 的**执行载体**（非判定器）。把"白名单精确 add → 暂存核验 → commit → push → 开 PR"
#       这条高度机械的链路从模型回合搬进脚本（proposal-012 §3④），削减全卡最贵的尾部回合。
#       判定式本体不动（ADR-005 语义不变）；异常一律**即停报出**，绝不自行 rebase/合并/force。
#
# 契约（spec AC-5 ~ AC-8 / AC-21 / AC-22）：
#   AC-5  git add 仅对入参白名单逐条精确执行（pathspec `:(literal,top)` 字面量，禁 -A / . / 通配符泛化）
#   AC-6  add 后以 `git diff --cached --name-status -z`（NUL 分隔原始字节 · 免疫 core.quotepath）核验：
#         白名单路径未进暂存（pathspec 缺失信号）、暂存区出现白名单外路径（污染信号）、
#         大范围 delete/rename（危险信号）→ 报错退出、不 commit
#         白名单条目可为**文件或目录**（阶段 7 现实用法大量是整卡目录 add，如 `--file .harness/changes/<卡>/`）：
#         目录条目按**前缀**核验（其下至少一个改动进暂存 = 命中；暂存路径落在某目录条目前缀下 = 不算污染），
#         仍是 `:(literal,top)<dir>` 精确 pathspec —— **不退化成 `-A` / `.` 泛化 add**（AC-5 属性不变）。
#   AC-7  核验通过 → commit → push → gh pr create；探测到 push 被拒（non-fast-forward / 落后基线分支）
#         → 即停并提示"需人工走 re-sync 流程"，不自动 rebase / 不自动合并 / 不 force-push
#   AC-8  全文不含 merge 子命令字面，不执行任何合并动作
#   AC-21 纯 shell + 既有 git/gh CLI，无 API key、无外部网络引擎
#   AC-22 只推变更分支（拒绝 base/main），不改业务代码文件（只动暂存区 + 远端分支 + PR）
#
# 授权（DF-007 / T2 授权硬门）：本脚本的调用形态已被 `pre_bash_guard.sh` 的 T2 gate 识别面覆盖
#   （本卡 T2′：`bash stage7_push.sh …` 等执行形态 → 归入 push gate → 走同一套用户授权台账判定）。
#   无用户显式授权时，调用本脚本的 Bash 命令会在 hook 层被 deny，脚本根本不会启动。
#
# 用法：
#   bash .harness/scripts/stage7_push.sh \
#     --card-dir .harness/changes/<变更目录> \
#     --branch change/<type>-<slug>-<YYYYMMDD> \
#     --message-file /tmp/commit_msg.txt \
#     --file <path1> --file <path2> ...
#
# 参数：
#   --card-dir <dir>        变更卡目录（须存在；用于 PR 正文默认引用）
#   --branch <name>         预期当前分支（须与实际当前分支一致——脚本**不切分支**，不一致即报错）
#   --message <text>        完整 commit message（原文透传，含 Co-Authored-By 尾巴由调用方提供）
#   --message-file <path>   从文件读取完整 commit message（与 --message 二选一，多行首选此形态）
#   --file <path>           白名单路径（可重复）；**文件或目录**均可（目录 = 其下全部改动，按前缀核验）；
#                           亦可在 `--` 之后以位置参数追加
#   --remote <name>         远端名（默认 origin）
#   --base <branch>         基线分支（默认 main）
#   --pr-title <text>       PR 标题（默认取 commit message 首行）
#   --pr-body-file <path>   PR 正文文件（默认生成引用变更卡的最小正文）
#   --no-pr                 只推送，不开 PR
#   --dry-run               只做 add + 核验，打印计划后退出（不 commit / 不 push / 不开 PR）
#   --allow-behind-base     显式放行"落后基线分支"（默认即停，走 re-sync）
#   --allow-destructive     显式放行大范围 delete/rename（默认阈值见 HARNESS_PUSH_MAX_DESTRUCTIVE）
#   -h | --help             打印本用法
#
# 环境变量：
#   HARNESS_PUSH_MAX_DESTRUCTIVE  暂存区 delete/rename 条目数上限（默认 20，超过 → 危险信号即停）
#
# 退出码：
#   0 成功（或 --dry-run 核验通过）
#   1 用法/参数错误（含分支不符、白名单为空、卡目录不存在）
#   2 暂存核验失败（AC-6：pathspec 缺失 / 暂存区污染 / 危险信号）
#   3 需人工 re-sync（AC-7：落后远端分支或基线分支 / push 被拒）
#   4 commit 失败
#   5 push 成功但 PR 创建失败（需人工开 PR）
set -uo pipefail

SCRIPT_NAME="stage7_push.sh"

usage() {
  sed -n '2,59p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'   # 头部注释块（至 set -uo pipefail 前一行）
}

log()  { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '[%s] ⚠ %s\n' "$SCRIPT_NAME" "$*" >&2; }
die()  { local code="$1"; shift; printf '[%s] ✗ %s\n' "$SCRIPT_NAME" "$*" >&2; exit "$code"; }

# ---------- 参数解析 ----------
card_dir=""
branch=""
message=""
message_file=""
remote="origin"
base="main"
pr_title=""
pr_body_file=""
no_pr=0
dry_run=0
allow_behind_base=0
allow_destructive=0
whitelist=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --card-dir)          card_dir="${2:-}"; shift 2 ;;
    --card-dir=*)        card_dir="${1#--card-dir=}"; shift ;;
    --branch)            branch="${2:-}"; shift 2 ;;
    --branch=*)          branch="${1#--branch=}"; shift ;;
    --message|-m)        message="${2:-}"; shift 2 ;;
    --message=*)         message="${1#--message=}"; shift ;;
    --message-file)      message_file="${2:-}"; shift 2 ;;
    --message-file=*)    message_file="${1#--message-file=}"; shift ;;
    --file|-f)           whitelist+=("${2:-}"); shift 2 ;;
    --file=*)            whitelist+=("${1#--file=}"); shift ;;
    --remote)            remote="${2:-}"; shift 2 ;;
    --remote=*)          remote="${1#--remote=}"; shift ;;
    --base)              base="${2:-}"; shift 2 ;;
    --base=*)            base="${1#--base=}"; shift ;;
    --pr-title)          pr_title="${2:-}"; shift 2 ;;
    --pr-title=*)        pr_title="${1#--pr-title=}"; shift ;;
    --pr-body-file)      pr_body_file="${2:-}"; shift 2 ;;
    --pr-body-file=*)    pr_body_file="${1#--pr-body-file=}"; shift ;;
    --no-pr)             no_pr=1; shift ;;
    --dry-run)           dry_run=1; shift ;;
    --allow-behind-base) allow_behind_base=1; shift ;;
    --allow-destructive) allow_destructive=1; shift ;;
    -h|--help)           usage; exit 0 ;;
    --)                  shift; while [ "$#" -gt 0 ]; do whitelist+=("$1"); shift; done ;;
    -*)                  die 1 "未知参数：$1（-h 看用法）" ;;
    *)                   whitelist+=("$1"); shift ;;
  esac
done

[ -n "$branch" ]   || die 1 "缺 --branch（预期当前分支）"
[ -n "$card_dir" ] || die 1 "缺 --card-dir（变更卡目录）"
[ "${#whitelist[@]}" -gt 0 ] || die 1 "缺 --file（文件白名单至少一条）——本脚本不做泛化 add"

# commit message：原文透传，脚本不拼接、不篡改（含 Co-Authored-By 尾巴由调用方一并提供）
if [ -n "$message_file" ]; then
  [ -n "$message" ] && die 1 "--message 与 --message-file 互斥"
  [ -r "$message_file" ] || die 1 "commit message 文件不可读：$message_file"
  message="$(cat "$message_file")"
fi
if [ "$dry_run" -eq 0 ]; then
  [ -n "$message" ] || die 1 "缺 commit message（--message 或 --message-file）"
fi

# ---------- 仓库与分支前置校验（AC-22：只推变更分支）----------
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die 1 "当前目录不在 git 仓库内"
cd "$repo_root" || die 1 "无法进入仓库根：$repo_root"

cur_branch="$(git branch --show-current 2>/dev/null)"
[ -n "$cur_branch" ] || die 1 "无法确定当前分支（detached HEAD？）——脚本不切分支，请人工处理"
if [ "$cur_branch" != "$branch" ]; then
  die 1 "当前分支（$cur_branch）与 --branch（$branch）不一致。脚本**不切分支**（DF-011）：请人工 checkout 后重跑。"
fi
if [ "$branch" = "$base" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  die 1 "拒绝：目标分支为基线分支（$branch）。DF-007：禁止直推 main，只在变更分支 push 并开 PR。"
fi

[ -d "$card_dir" ] || die 1 "变更卡目录不存在：$card_dir"

# ---------- AC-5：白名单精确 add（禁 -A / . / 通配符泛化）----------
# 逐条 pathspec 精确 add，pathspec 前缀 `:(literal,top)` = 关闭 glob 展开 + 锚定仓库根；
# 白名单外文件即便有改动也不会被 stage（下方 AC-6 核验再兜一层）。
norm_whitelist=()
for p in "${whitelist[@]}"; do
  [ -n "$p" ] || die 1 "白名单含空路径条目"
  # 绝对路径 → 归一为仓库根相对路径
  case "$p" in
    "$repo_root"/*) p="${p#"$repo_root"/}" ;;
    /*) die 1 "白名单路径不在本仓库内：$p" ;;
  esac
  p="${p#./}"
  # 目录条目的尾斜杠归一（`--file <dir>/` 与 `--file <dir>` 视作同一条目；下方前缀核验依赖无尾斜杠形态）
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  # 泛化 add 形态一律拒绝（AC-5）
  case "$p" in
    -A|-a|--all|.|./|/|"") die 1 "白名单拒绝泛化 add 形态：'$p'（AC-5：只接受精确路径）" ;;
    *[\*\?\[]*)            die 1 "白名单拒绝通配符：'$p'（AC-5：只接受精确路径，pathspec 按字面量处理）" ;;
    :*)                    die 1 "白名单拒绝 pathspec magic：'$p'（AC-5：只接受精确路径）" ;;
  esac
  norm_whitelist+=("$p")
done

# 条目分型（S-2）：目录条目走前缀核验，文件条目走全等核验。
# 分型只影响**核验口径**，add 仍是逐条 `:(literal,top)<path>` 精确 pathspec（AC-5 不变）。
wl_files=()
wl_dirs=()
for p in "${norm_whitelist[@]}"; do
  if [ -d "$p" ]; then wl_dirs+=("$p"); else wl_files+=("$p"); fi
done

log "仓库根：$repo_root"
log "分支：$branch（基线 $base · 远端 $remote）"
log "白名单 ${#norm_whitelist[@]} 条 → 逐条精确 add"
for p in "${norm_whitelist[@]}"; do
  git add -- ":(literal,top)$p" \
    || die 2 "git add 失败：$p（路径不存在？）"
  printf '  + %s\n' "$p"
done

# ---------- AC-6：暂存核验（pathspec 缺失 / 暂存区污染 / 危险信号）----------
# 路径解析一律走 `--name-status -z`（NUL 分隔的**原始字节**），不用默认的 tab 分隔文本形态：
#   git 默认 `core.quotepath=true`，对**非 ASCII 路径**输出的是带双引号的八进制转义串
#   （`"plugins/.../\345\267\245\347\250\213\347\273\223\346\236\204.md"`）。拿它与白名单里的字面
#   UTF-8 路径比对必然比不上 → 中文名路径被全体误判为「pathspec 缺失」而即停（阶段 7 实测触发；
#   本仓规范文件大量是中文名，且消费方项目凡有非 ASCII 文件名同理 → 脚本形同不可用）。
#   `-z` 比 `-c core.quotepath=false` 更彻底：后者只关"非 ASCII 转义"，路径含空格/制表符/换行/双引号
#   时仍会被 C-quote 并加引号，照样毒化解析；`-z` 则一律输出原始字节，无引号无转义。
#   代价：NUL 无法经 `$(...)` 捕获（bash 变量丢 NUL 字节 → 整串会被拼成一坨），故落临时文件再按 NUL 读。
staged_z="$(mktemp)"
trap 'rm -f "$staged_z" 2>/dev/null || true' EXIT
git diff --cached --name-status -z >"$staged_z" \
  || die 2 "git diff --cached 执行失败，无法核验暂存区"

if [ ! -s "$staged_z" ]; then
  die 2 "暂存区为空：白名单 ${#norm_whitelist[@]} 条路径 add 后无任何变更进入暂存区。
  → 典型成因（§6.1 教训）：pathspec 写错层级 / 文件其实无改动 / 改动已被提交。
  → 脚本即停，不产生空 commit。"
fi

# `-z` 记录布局：`<status>\0<path>\0`；R/C（rename/copy）多一个路径字段 → `<status>\0<src>\0<dst>\0`。
# 字段读不全 = 解析失败 → 即停（fail-closed：宁可停也不拿残缺清单去放行 commit）。
staged_paths=()
destructive=0
while IFS= read -r -d '' st; do
  [ -n "$st" ] || continue
  case "$st" in
    R*) IFS= read -r -d '' p1 || die 2 "暂存清单解析失败：rename 记录（$st）缺源路径字段"
        IFS= read -r -d '' p2 || die 2 "暂存清单解析失败：rename 记录（$st）缺目标路径字段"
        staged_paths+=("$p1" "$p2"); destructive=$((destructive + 1)) ;;
    C*) IFS= read -r -d '' p1 || die 2 "暂存清单解析失败：copy 记录（$st）缺源路径字段"
        IFS= read -r -d '' p2 || die 2 "暂存清单解析失败：copy 记录（$st）缺目标路径字段"
        staged_paths+=("$p2") ;;
    D*) IFS= read -r -d '' p1 || die 2 "暂存清单解析失败：delete 记录（$st）缺路径字段"
        staged_paths+=("$p1");                destructive=$((destructive + 1)) ;;
    *)  IFS= read -r -d '' p1 || die 2 "暂存清单解析失败：记录（$st）缺路径字段"
        staged_paths+=("$p1") ;;
  esac
done < "$staged_z"

in_list() {  # $1 = 待查路径；$2.. = 集合
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# S-2：目录条目命中判据 —— 暂存清单中存在该目录**前缀**下的路径（`git diff --cached --name-status`
# 只列文件级路径，目录名本身永远不会出现在其中；修前的全等比较故对目录条目恒判「缺失」并误报诊断）。
dir_has_staged() {  # $1 = 目录条目（无尾斜杠）
  local d="$1" sp
  for sp in "${staged_paths[@]}"; do
    [ -n "$sp" ] || continue
    case "$sp" in "$d"/*) return 0 ;; esac
  done
  return 1
}

# S-2：暂存路径是否被白名单覆盖（文件条目全等 · 目录条目前缀）。
covered_by_whitelist() {  # $1 = 暂存路径
  local sp="$1" item
  for item in ${wl_files[@]+"${wl_files[@]}"}; do
    [ "$item" = "$sp" ] && return 0
  done
  for item in ${wl_dirs[@]+"${wl_dirs[@]}"}; do
    case "$sp" in "$item"/*) return 0 ;; esac
  done
  return 1
}

# ① pathspec 缺失信号：白名单路径未出现在 diff --cached 结果中 → 报错退出（不 commit）
missing=()
for p in ${wl_files[@]+"${wl_files[@]}"}; do
  in_list "$p" "${staged_paths[@]}" || missing+=("$p")
done
for p in ${wl_dirs[@]+"${wl_dirs[@]}"}; do
  dir_has_staged "$p" || missing+=("$p")
done
if [ "${#missing[@]}" -gt 0 ]; then
  {
    printf '[%s] ✗ 暂存核验失败（AC-6 · pathspec 缺失信号）：以下白名单路径未进入暂存区：\n' "$SCRIPT_NAME"
    for p in "${missing[@]}"; do
      if [ ! -e "$p" ]; then
        printf '  - %s（工作树中不存在 → 路径拼写/层级错误）\n' "$p"
      elif [ -d "$p" ]; then
        printf '  - %s/（目录存在，但其下无任何改动进入暂存区 → 疑似改动已提交 / 写错目录层级）\n' "$p"
      else
        printf '  - %s（存在但无改动 → 疑似已提交 / 写错目标文件）\n' "$p"
      fi
    done
    printf '  → 即停，不 commit。请核对白名单后重跑。\n'
  } >&2
  exit 2
fi

# ② 暂存区污染信号：出现白名单外的路径（如上轮残留的 staged 内容）→ 报错退出
extra=()
for p in "${staged_paths[@]}"; do
  [ -n "$p" ] || continue
  covered_by_whitelist "$p" || extra+=("$p")
done
if [ "${#extra[@]}" -gt 0 ]; then
  {
    printf '[%s] ✗ 暂存核验失败（AC-6 · 暂存区污染信号）：暂存区含白名单外路径：\n' "$SCRIPT_NAME"
    for p in "${extra[@]}"; do printf '  - %s\n' "$p"; done
    printf '  → 即停，不 commit。请先 `git restore --staged <path>` 清干净暂存区后重跑。\n'
  } >&2
  exit 2
fi

# ③ 危险信号：大范围 delete/rename（阈值可经 HARNESS_PUSH_MAX_DESTRUCTIVE 调整）
max_destructive="${HARNESS_PUSH_MAX_DESTRUCTIVE:-20}"
if [ "$destructive" -gt "$max_destructive" ] && [ "$allow_destructive" -eq 0 ]; then
  die 2 "暂存核验失败（AC-6 · 危险信号）：暂存区含 $destructive 条 delete/rename（阈值 $max_destructive）。
  → 即停，不 commit。确属预期请显式加 --allow-destructive（或调 HARNESS_PUSH_MAX_DESTRUCTIVE）。"
fi

log "暂存核验通过：${#norm_whitelist[@]} 条白名单全部在暂存区，无白名单外路径，delete/rename $destructive 条（阈值 $max_destructive）"
# 人读清单：显式 `core.quotepath=false`，非 ASCII 路径按 UTF-8 原样打印（默认会打成八进制转义串，
# Owner 在终端里根本认不出是哪个文件）。此处**只用于展示**，判定一律基于上方 `-z` 解析出的 staged_paths。
git -c core.quotepath=false diff --cached --name-status | sed 's/^/  /'
rm -f "$staged_z" 2>/dev/null || true

if [ "$dry_run" -eq 1 ]; then
  log "--dry-run：核验通过，就此停手（不 commit / 不 push / 不开 PR）"
  exit 0
fi

# ---------- AC-7 前置探测：落后远端 → 即停走 re-sync（不自动 rebase / 不自动 force）----------
# UQ-2 选型：以**结构化计数**（git rev-list --count）为主判据、push 退出码为最终权威，
# stderr 文本模式仅用于给失败**贴标签**——决策不依赖文本匹配（免疫 git 版本/语言环境的文案漂移）。
if git fetch --quiet "$remote" 2>/dev/null; then
  if git rev-parse --verify --quiet "refs/remotes/$remote/$branch" >/dev/null; then
    behind="$(git rev-list --count "HEAD..$remote/$branch" 2>/dev/null || echo 0)"
    if [ "${behind:-0}" -gt 0 ]; then
      die 3 "探测到落后远端同名分支 $remote/$branch $behind 个提交（non-fast-forward 前兆）。
  → 即停：**需人工走 re-sync 流程**（拉取远端改动 → 复核 → 全量复跑质量门）后重推。
  → 脚本不自动 rebase、不自动合并、不 force-push（DF-007 / AC-7）。"
    fi
  fi
  if git rev-parse --verify --quiet "refs/remotes/$remote/$base" >/dev/null; then
    behind_base="$(git rev-list --count "HEAD..$remote/$base" 2>/dev/null || echo 0)"
    if [ "${behind_base:-0}" -gt 0 ]; then
      if [ "$allow_behind_base" -eq 0 ]; then
        die 3 "探测到落后基线分支 $remote/$base $behind_base 个提交。
  → 即停：**需人工走 re-sync 流程**（同步基线 → 复核冲突 → 全量复跑质量门）后重推。
  → 脚本不自动 rebase、不自动合并、不 force-push（DF-007 / AC-7）。
  → 确认无需同步可显式加 --allow-behind-base。"
      fi
      warn "落后基线分支 $remote/$base $behind_base 个提交（--allow-behind-base 已显式放行，继续推送）"
    fi
  fi
else
  warn "git fetch $remote 失败（网络/权限？）：跳过前置落后探测，改由 push 退出码兜底判定"
fi

# ---------- commit（message 原文透传，不拼接不篡改）----------
commit_err="$(mktemp)"
trap 'rm -f "$commit_err" 2>/dev/null || true' EXIT
if ! printf '%s\n' "$message" | git commit --cleanup=whitespace -F - >"$commit_err" 2>&1; then
  cat "$commit_err" >&2
  die 4 "git commit 失败（详见上方输出）。暂存区保持原样，未 push。"
fi
head_sha="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
log "commit 完成：$head_sha"

# ---------- push（AC-7：被拒即停，不自动 rebase / 不 force）----------
push_err="$(mktemp)"
trap 'rm -f "$commit_err" "$push_err" 2>/dev/null || true' EXIT
if ! git push -u "$remote" "$branch" >"$push_err" 2>&1; then
  cat "$push_err" >&2
  label="push 被远端拒绝"
  if grep -qiE 'non-fast-forward|fetch first|rejected|stale info|behind its remote' "$push_err" 2>/dev/null; then
    label="push 被拒（non-fast-forward / 落后远端）"
  fi
  die 3 "$label。
  → 即停：**需人工走 re-sync 流程**（拉取远端改动 → 复核 → 全量复跑质量门）后重推。
  → 脚本不自动 rebase、不自动合并、不 force-push（DF-007 / AC-7）。
  → 本地 commit $head_sha 已生成并保留（re-sync 后可直接重推，无需重做）。"
fi
log "push 完成：$remote/$branch"

if [ "$no_pr" -eq 1 ]; then
  log "--no-pr：跳过 PR 创建。DONE（commit=$head_sha）"
  exit 0
fi

# ---------- gh pr create（已存在则复用，不新建；本脚本不做任何合并动作 · AC-8）----------
if ! command -v gh >/dev/null 2>&1; then
  die 5 "push 已成功（$remote/$branch @ $head_sha），但 gh CLI 不可用 → PR 未创建，需人工开 PR。"
fi

existing_pr="$(gh pr view "$branch" --json url --jq .url 2>/dev/null || true)"
if [ -n "$existing_pr" ]; then
  log "PR 已存在，复用（不新建）：$existing_pr"
  log "DONE（commit=$head_sha · PR=$existing_pr）"
  exit 0
fi

[ -n "$pr_title" ] || pr_title="$(printf '%s\n' "$message" | head -1)"

pr_body_tmp=""
if [ -z "$pr_body_file" ]; then
  pr_body_tmp="$(mktemp)"
  trap 'rm -f "$commit_err" "$push_err" "$pr_body_tmp" 2>/dev/null || true' EXIT
  {
    printf '## 变更卡\n\n`%s`\n\n' "$card_dir"
    printf '详见该目录下 `summary.md`（10 阶段产物 SSOT）。\n\n'
    printf '## commit\n\n`%s`\n\n' "$head_sha"
    printf -- '---\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n'
  } > "$pr_body_tmp"
  pr_body_file="$pr_body_tmp"
fi
[ -r "$pr_body_file" ] || die 5 "push 已成功但 PR 正文文件不可读：$pr_body_file（需人工开 PR）"

pr_url="$(gh pr create --base "$base" --head "$branch" \
  --title "$pr_title" --body-file "$pr_body_file" 2>&1)" || {
  printf '%s\n' "$pr_url" >&2
  die 5 "push 已成功（$remote/$branch @ $head_sha），但 gh pr create 失败（详见上方输出）→ 需人工开 PR。"
}
printf '%s\n' "$pr_url" | tail -1
log "DONE（commit=$head_sha · 分支已推送 · PR 已创建）。合并动作不在本脚本范围内——须经 HITL-5 人工授权。"
exit 0
