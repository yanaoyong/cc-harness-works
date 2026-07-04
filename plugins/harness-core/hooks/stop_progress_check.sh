#!/usr/bin/env bash
# Stop 钩子：会话结束时检查是否有变更目录的 summary.md 最近被更新（对应 DF-006 / docs/stage-01-Harness体系建设/03-质量与改进/09-变更管理与持久化记忆规范.md）
# 仅提示，不阻断（非强制；如需强制可改为退出码 2）
#
# 自定位策略（解决 failure-record-001-stop-hook-path）：
#   1) 优先 git rev-parse --show-toplevel        → 当前 worktree 根
#   2) 若身在 git worktree，再补主仓根            → dirname(git rev-parse --git-common-dir)
#   3) git 不可用时回退 $CLAUDE_PROJECT_DIR       → Claude Code 注入
#   4) 最后回退 $PWD                              → 至少保证脚本本体可运行
# 扫描结果：上述任一根的 .harness/changes 中 24h 内有非 _TEMPLATE 的 summary.md 即视为"近更新"。
# 明确不加 -e：hook 须容错不中途中止、任何路径最终 exit 0；加 -e 会让首个非 0 命令绕过收尾。
set -uo pipefail

# resolve_roots 单点化于 lib/shell-utils.sh（TG-1）。lib 路径由本脚本路径相对推得（不依赖 cwd），
# lib 不可读 → 退回内联兜底（AC-1.4 优雅降级 · 逐字同原实现 · 不崩）。
_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
_SU_LIB="$_HOOK_DIR/../../.harness/scripts/lib/shell-utils.sh"
[ -r "$_SU_LIB" ] && . "$_SU_LIB"

if ! type resolve_roots >/dev/null 2>&1; then
  # 内联兜底（lib 缺失时）——与 lib/shell-utils.sh resolve_roots 逐字等价
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
fi

found=""
scanned=0
while IFS= read -r root; do
  [ -z "$root" ] && continue
  changes_dir="$root/.harness/changes"
  [ ! -d "$changes_dir" ] && continue
  scanned=$((scanned + 1))
  recent="$(find "$changes_dir" -name summary.md -not -path '*/_TEMPLATE/*' -mtime -1 2>/dev/null | head -1 || true)"
  if [ -n "$recent" ]; then
    found="$recent"
    break
  fi
done < <(resolve_roots)

if [ "$scanned" -eq 0 ]; then
  echo "[harness:stop_progress_check] 提示：未在当前会话定位到 .harness/changes 目录（已尝试 git 根、CLAUDE_PROJECT_DIR、PWD）。" >&2
  exit 0
fi

if [ -z "$found" ]; then
  echo "[harness:stop_progress_check] 提醒：本次会话未见 summary.md 更新（已扫描 ${scanned} 个根）。请确认每阶段完成后已覆盖式更新 summary.md（DF-006 / docs/stage-01-Harness体系建设/03-质量与改进/09-变更管理与持久化记忆规范.md）。" >&2
fi
exit 0
