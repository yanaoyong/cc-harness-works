#!/usr/bin/env bash
# SessionStart 钩子：会话启动时自动把本地 main 快进（ff-only）同步到 origin/main。
# 设计原则（spec FR-1..7）：守卫齐全才动手，否则静默退出 0，永不阻断会话。
#
# 短路顺序固定为 ①分支==main → ②工作树干净 → fetch(带超时·fail-open) → ③落后判定 → ff-only 合并。
# 守卫① / ② 在 fetch 之前求值，任一不满足即不执行 fetch/merge、直接退出 0。
# 所有提示走 stderr，统一前缀 [harness:session_autosync]；任何路径最终 exit 0。
# bash 3.2 兼容：不使用 declare -A / 关联数组 / mapfile / readarray / bash4-only 语法。
set -uo pipefail

PREFIX="[harness:session_autosync]"

# FR-1 自定位仓库根；非 git / 定位失败 → 静默退出 0
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TOP" ] && exit 0
cd "$TOP" || exit 0

# FR-2① 当前分支必须 == main（detached HEAD 返回 HEAD ≠ main，自然被拦截）
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[ "$branch" = "main" ] || exit 0

# FR-2② 工作树必须干净
[ -z "$(git status --porcelain 2>/dev/null)" ] || exit 0

# FR-3 fetch 带超时 + fail-open（仅在守卫①② 通过后执行）
# timeout 命令在 macOS 默认缺失：优先 timeout / gtimeout，否则退化为不带超时的直接 fetch（仍保 fail-open）。
if command -v timeout >/dev/null 2>&1; then
  timeout 5 git fetch origin main >/dev/null 2>&1
  fetch_rc=$?
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout 5 git fetch origin main >/dev/null 2>&1
  fetch_rc=$?
else
  git fetch origin main >/dev/null 2>&1
  fetch_rc=$?
fi

if [ "$fetch_rc" -ne 0 ]; then
  echo "$PREFIX fetch 失败或超时，跳过本次自动同步（不影响会话）" >&2
  exit 0
fi

# 落后判定与 merge 目标均指向刚 fetch 到的远端 main（FETCH_HEAD），不依赖可能过期的 remote-tracking ref。
# FR-2③ 落后判定（放在 fetch 之后）
behind="$(git rev-list --count HEAD..FETCH_HEAD 2>/dev/null || echo 0)"
[ "$behind" -gt 0 ] 2>/dev/null || exit 0

# FR-4 只 ff-only 合并；分叉无法快进 → 捕获、保留本地提交、退出 0
if git merge --ff-only FETCH_HEAD >/dev/null 2>&1; then
  echo "$PREFIX 本地 main 已快进同步 origin/main（+${behind}）" >&2
else
  echo "$PREFIX 本地 main 与 origin/main 分叉，跳过自动同步（保留本地提交，请手动处理）" >&2
fi

# FR-5 永不阻断
exit 0
