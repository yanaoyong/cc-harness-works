#!/usr/bin/env bash
# SessionStart hook: refresh origin/main, then safely fast-forward the local main branch.
# All failures are fail-open so SessionStart is never blocked. User-facing diagnostics go to stderr.
# Bash 3.2 compatible: no associative arrays, mapfile, readarray, or Bash 4-only syntax.
set -uo pipefail

PREFIX="[harness:session_autosync]"

notice() {
  printf '%s %s\n' "$PREFIX" "$1" >&2
}

# Worktree parser state. A record starts with "worktree <path>" and ends at a blank line.
finish_worktree_record() {
  [ "$WT_RECORD_ACTIVE" -eq 1 ] || return 0

  case "$WT_RECORD_PATH" in
    /*) ;;
    *) WT_PARSE_ERROR=1 ;;
  esac

  if [ "$WT_RECORD_LOCKED_COUNT" -gt 1 ] || [ "$WT_RECORD_PRUNABLE_COUNT" -gt 1 ]; then
    WT_PARSE_ERROR=1
  fi

  if [ "$WT_RECORD_BARE_COUNT" -eq 1 ]; then
    # Real bare-repository porcelain has only "worktree <path>" plus "bare".
    if [ "$WT_RECORD_HEAD_COUNT" -ne 0 ] || [ "$WT_RECORD_BRANCH_COUNT" -ne 0 ] || \
       [ "$WT_RECORD_DETACHED_COUNT" -ne 0 ] || [ "$WT_RECORD_LOCKED_COUNT" -ne 0 ] || \
       [ "$WT_RECORD_PRUNABLE_COUNT" -ne 0 ]; then
      WT_PARSE_ERROR=1
    fi
  elif [ "$WT_RECORD_BARE_COUNT" -eq 0 ]; then
    # A non-bare record has one HEAD and exactly one mutually exclusive checkout state.
    if [ "$WT_RECORD_HEAD_COUNT" -ne 1 ] || \
       { [ "$WT_RECORD_BRANCH_COUNT" -ne 1 ] && [ "$WT_RECORD_DETACHED_COUNT" -ne 1 ]; } || \
       { [ "$WT_RECORD_BRANCH_COUNT" -ne 0 ] && [ "$WT_RECORD_DETACHED_COUNT" -ne 0 ]; }; then
      WT_PARSE_ERROR=1
    fi
  else
    WT_PARSE_ERROR=1
  fi

  if [ "$WT_RECORD_PATH" = "$TOP" ]; then
    if [ "$WT_RECORD_BARE_COUNT" -ne 0 ]; then
      WT_PARSE_ERROR=1
    else
      WT_CURRENT_COUNT=$((WT_CURRENT_COUNT + 1))
      if [ "$WT_MODE" = "current-main" ] && [ "$WT_RECORD_MAIN" -ne 1 ]; then
        WT_PARSE_ERROR=1
      fi
    fi
  fi

  if [ "$WT_RECORD_MAIN" -eq 1 ]; then
    if [ "$WT_MODE" != "current-main" ] || [ "$WT_RECORD_PATH" != "$TOP" ]; then
      if [ -z "$WT_BLOCK_PATH" ]; then
        WT_BLOCK_PATH="$WT_RECORD_PATH"
      fi
    fi
  fi

  WT_RECORD_ACTIVE=0
  WT_RECORD_PATH=""
  WT_RECORD_MAIN=0
  WT_RECORD_HEAD_COUNT=0
  WT_RECORD_BARE_COUNT=0
  WT_RECORD_BRANCH_COUNT=0
  WT_RECORD_DETACHED_COUNT=0
  WT_RECORD_LOCKED_COUNT=0
  WT_RECORD_PRUNABLE_COUNT=0
}

# Return 0 when main is free, 1 when a worktree occupies main, and 2 when parsing is unsafe.
inspect_main_worktrees() {
  WT_MODE="$1"
  WT_BLOCK_PATH=""
  WT_PARSE_ERROR=0
  WT_CURRENT_COUNT=0
  WT_RECORD_ACTIVE=0
  WT_RECORD_PATH=""
  WT_RECORD_MAIN=0
  WT_RECORD_HEAD_COUNT=0
  WT_RECORD_BARE_COUNT=0
  WT_RECORD_BRANCH_COUNT=0
  WT_RECORD_DETACHED_COUNT=0
  WT_RECORD_LOCKED_COUNT=0
  WT_RECORD_PRUNABLE_COUNT=0

  worktree_output="$(git worktree list --porcelain 2>/dev/null)"
  worktree_rc=$?
  if [ "$worktree_rc" -ne 0 ]; then
    return 2
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$line" ]; then
      finish_worktree_record
      continue
    fi

    case "$line" in
      worktree\ *)
        if [ "$WT_RECORD_ACTIVE" -eq 1 ]; then
          WT_PARSE_ERROR=1
          finish_worktree_record
        fi
        WT_RECORD_ACTIVE=1
        WT_RECORD_PATH=${line#worktree }
        [ -n "$WT_RECORD_PATH" ] || WT_PARSE_ERROR=1
        ;;
      HEAD\ *)
        head_value=${line#HEAD }
        if [ "$WT_RECORD_ACTIVE" -ne 1 ] || [ -z "$head_value" ]; then
          WT_PARSE_ERROR=1
        else
          WT_RECORD_HEAD_COUNT=$((WT_RECORD_HEAD_COUNT + 1))
          case "$head_value" in
            *[!0-9a-f]*) WT_PARSE_ERROR=1 ;;
          esac
          if [ "${#head_value}" -ne 40 ] && [ "${#head_value}" -ne 64 ]; then
            WT_PARSE_ERROR=1
          fi
        fi
        ;;
      branch\ *)
        branch_value=${line#branch }
        if [ "$WT_RECORD_ACTIVE" -ne 1 ] || [ -z "$branch_value" ]; then
          WT_PARSE_ERROR=1
        else
          WT_RECORD_BRANCH_COUNT=$((WT_RECORD_BRANCH_COUNT + 1))
          case "$branch_value" in
            refs/heads/?*) ;;
            *) WT_PARSE_ERROR=1 ;;
          esac
          if [ "$branch_value" = "refs/heads/main" ]; then
            WT_RECORD_MAIN=1
          fi
        fi
        ;;
      detached)
        if [ "$WT_RECORD_ACTIVE" -ne 1 ]; then
          WT_PARSE_ERROR=1
        else
          WT_RECORD_DETACHED_COUNT=$((WT_RECORD_DETACHED_COUNT + 1))
        fi
        ;;
      bare)
        if [ "$WT_RECORD_ACTIVE" -ne 1 ]; then
          WT_PARSE_ERROR=1
        else
          WT_RECORD_BARE_COUNT=$((WT_RECORD_BARE_COUNT + 1))
        fi
        ;;
      locked|locked\ *)
        if [ "$WT_RECORD_ACTIVE" -ne 1 ]; then
          WT_PARSE_ERROR=1
        else
          WT_RECORD_LOCKED_COUNT=$((WT_RECORD_LOCKED_COUNT + 1))
        fi
        ;;
      prunable|prunable\ *)
        if [ "$WT_RECORD_ACTIVE" -ne 1 ]; then
          WT_PARSE_ERROR=1
        else
          WT_RECORD_PRUNABLE_COUNT=$((WT_RECORD_PRUNABLE_COUNT + 1))
        fi
        ;;
      *)
        WT_PARSE_ERROR=1
        ;;
    esac
  done <<EOF_WORKTREES
$worktree_output
EOF_WORKTREES

  finish_worktree_record

  if [ "$WT_PARSE_ERROR" -ne 0 ] || [ "$WT_CURRENT_COUNT" -ne 1 ]; then
    return 2
  fi
  [ -z "$WT_BLOCK_PATH" ] || return 1
  return 0
}

# Non-git directories are intentionally silent.
TOP="$(git rev-parse --show-toplevel 2>/dev/null)"
top_rc=$?
if [ "$top_rc" -ne 0 ] || [ -z "$TOP" ]; then
  exit 0
fi
if ! cd "$TOP" 2>/dev/null; then
  notice "无法进入仓库根目录，跳过本次自动同步"
  exit 0
fi

# Refresh the exact remote-tracking ref regardless of the currently checked-out branch.
if command -v timeout >/dev/null 2>&1; then
  timeout 5 git fetch --force origin 'refs/heads/main:refs/remotes/origin/main' >/dev/null 2>&1
  fetch_rc=$?
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout 5 git fetch --force origin 'refs/heads/main:refs/remotes/origin/main' >/dev/null 2>&1
  fetch_rc=$?
else
  git fetch --force origin 'refs/heads/main:refs/remotes/origin/main' >/dev/null 2>&1
  fetch_rc=$?
fi

if [ "$fetch_rc" -ne 0 ]; then
  notice "fetch 失败或超时，跳过本次自动同步（不影响会话）"
  exit 0
fi

remote_sha="$(git rev-parse --verify 'refs/remotes/origin/main^{commit}' 2>/dev/null)"
remote_rc=$?
if [ "$remote_rc" -ne 0 ] || [ -z "$remote_sha" ]; then
  notice "无法验证 refs/remotes/origin/main 为提交，跳过本次自动同步"
  exit 0
fi

old_main_sha="$(git rev-parse --verify 'refs/heads/main^{commit}' 2>/dev/null)"
main_rc=$?
if [ "$main_rc" -ne 0 ] || [ -z "$old_main_sha" ]; then
  notice "本地 main 不存在或无法解析，不自动创建"
  exit 0
fi

# Equal is the idempotent, silent path.
if [ "$old_main_sha" = "$remote_sha" ]; then
  exit 0
fi

# Classify behind/ahead/diverged while preserving command errors as a distinct safe skip.
git merge-base --is-ancestor "$old_main_sha" "$remote_sha" >/dev/null 2>&1
forward_rc=$?
case "$forward_rc" in
  0)
    ;;
  1)
    git merge-base --is-ancestor "$remote_sha" "$old_main_sha" >/dev/null 2>&1
    reverse_rc=$?
    case "$reverse_rc" in
      0)
        notice "本地 main 领先 origin/main，保留本地提交"
        exit 0
        ;;
      1)
        notice "本地 main 与 origin/main 已分叉，保留双方提交"
        exit 0
        ;;
      *)
        notice "无法安全判定 main 的提交关系，跳过本次自动同步"
        exit 0
        ;;
    esac
    ;;
  *)
    notice "无法安全判定 main 的提交关系，跳过本次自动同步"
    exit 0
    ;;
esac

head_ref="$(git symbolic-ref -q HEAD 2>/dev/null)"
head_ref_rc=$?
if [ "$head_ref_rc" -ne 0 ] && [ "$head_ref_rc" -ne 1 ]; then
  notice "无法安全判定当前分支，跳过本次自动同步"
  exit 0
fi

if [ "$head_ref" = "refs/heads/main" ]; then
  # A checked-out main must be clean because merge updates HEAD, index, and working tree.
  status_output="$(git status --porcelain=v1 --untracked-files=all 2>/dev/null)"
  status_rc=$?
  if [ "$status_rc" -ne 0 ]; then
    notice "无法检查当前 main 工作树状态，跳过本次自动同步"
    exit 0
  fi
  if [ -n "$status_output" ]; then
    notice "当前 main 工作树或索引不干净，跳过本次自动同步"
    exit 0
  fi

  # Keep this snapshot check adjacent to the worktree-aware update.
  inspect_main_worktrees "current-main"
  worktree_rc=$?
  if [ "$worktree_rc" -eq 2 ]; then
    notice "无法安全解析 worktree 占用状态，跳过本次自动同步"
    exit 0
  fi
  if [ "$worktree_rc" -eq 1 ]; then
    notice "main 已被其他 worktree 检出（${WT_BLOCK_PATH}），跳过本次自动同步"
    exit 0
  fi
  if ! git merge --ff-only "$remote_sha" >/dev/null 2>&1; then
    notice "main 快进合并失败，保留当前状态"
  fi
  exit 0
fi

# Feature and detached worktrees may be dirty: only the un-checked-out main ref is updated.
# Keep this snapshot check adjacent to the CAS update.
inspect_main_worktrees "non-main"
worktree_rc=$?
if [ "$worktree_rc" -eq 2 ]; then
  notice "无法安全解析 worktree 占用状态，跳过本次自动同步"
  exit 0
fi
if [ "$worktree_rc" -eq 1 ]; then
  notice "main 已被 worktree 检出（${WT_BLOCK_PATH}），跳过本次自动同步"
  exit 0
fi
if ! git update-ref refs/heads/main "$remote_sha" "$old_main_sha" >/dev/null 2>&1; then
  notice "main 并发更新或 CAS 快进失败，保留当前状态"
fi

exit 0
