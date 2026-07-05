#!/usr/bin/env bash
# lib/shell-utils.sh —— Harness hook/脚本公共工具函数单点（TG-1 · 防内联复制漂移）。
#
# 抽取自三处内联复制（逐字保语义，行为零回归）：
#   - resolve_root  ← .claude/hooks/static_security_scan.sh（单根三层 fallback）
#                    ← .claude/hooks/user_prompt_state_inject.sh（同型单根三层）
#   - resolve_roots ← .claude/hooks/stop_progress_check.sh（多根四层 · 含 worktree 主仓兜底）
# 供这些 hook source 共享，单点化"自定位仓库根"口径。
#
# 设计纪律（同 lib/merged_detect.sh）：
#   - 纯函数库、无副作用、不修改任何文件、不 commit/push。
#   - 被 source；不强设 `set -e`——本 lib 仅定义函数，被 source 时不应改变调用方 shell 选项
#     （hook 须容错不中途中止、最终 exit 0；强加 -e 会破坏调用方的 exit 0 收尾纪律）。
#   - bash 3.2 兼容：不使用 declare -A / 关联数组 / mapfile / readarray。

# resolve_root —— 单根自定位（三层 fallback · 逐字同 static_security_scan.sh 原 resolve_root）：
#   1) git rev-parse --show-toplevel    → 当前 worktree 根
#   2) ${CLAUDE_PROJECT_DIR:-}           → Claude Code 注入
#   3) $PWD                              → 至少保证脚本本体可运行
# stdout 输出单个根路径；恒返回 0。
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

# resolve_roots —— 多根自定位（四层 · 逐字同 stop_progress_check.sh 原 resolve_roots）：
#   1) git rev-parse --show-toplevel                   → 当前 worktree 根
#   2) 身在 git worktree 时再补主仓根 = dirname(git rev-parse --git-common-dir)
#      （仅当与当前根不同才输出 · 解决 failure-record-001-stop-hook-path）
#   3) git 不可用时回退 ${CLAUDE_PROJECT_DIR:-}
#   4) 最后回退 $PWD
# stdout 逐行输出一个或多个根路径；恒返回 0。
resolve_roots() {
  local top common common_abs main
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then
    printf '%s\n' "$top"
    common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
    if [ -n "$common" ]; then
      common_abs="$(cd "$common" 2>/dev/null && pwd || true)"
      if [ -n "$common_abs" ]; then
        main="$(dirname "$common_abs")"
        if [ -n "$main" ] && [ "$main" != "$top" ]; then
          printf '%s\n' "$main"
        fi
      fi
    fi
    return 0
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  printf '%s\n' "$PWD"
}

# warn <msg> —— 统一 stderr warning 输出（不阻断 · 不改退出码）。
warn() { printf 'warning: %s\n' "$1" >&2; }

# die <msg> [code] —— stderr 报错并退出（默认码 1）。
# 注意：仅供"确需中止"的脚本调用；hook/维护脚本须容错不中止，勿用 die。
die() { printf 'error: %s\n' "$1" >&2; exit "${2:-1}"; }
