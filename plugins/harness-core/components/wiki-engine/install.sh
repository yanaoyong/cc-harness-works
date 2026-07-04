#!/usr/bin/env bash
# install.sh — 把 wiki-engine 注册为宿主仓库的项目级 skill。
#
# 与 llm-wiki 的 install 不同，本 skill 是"仓库耦合"的：脚本按仓库根相对
# 路径运行（权限白名单也按该路径放行），wiki 内容就在仓库里。因此安装 =
# 在宿主仓库 .claude/skills/ 下建一个指回 .harness/components/wiki-engine 的符号链接，
# 让 Claude Code（含 -p 无头会话）能发现并触发它。不复制文件、不碰 PATH。
#
# 副作用最小可回滚：只创建一个符号链接。卸载 = 删除该链接。
#
# 用法（在宿主仓库根运行）：
#   .harness/components/wiki-engine/install.sh [--repo-root <path>]
#   也可经 WIKI_ENGINE_REPO_ROOT 环境变量显式指定仓库根（plugin 分发器注入点）。
set -euo pipefail

say() { printf '%s\n' "$*"; }

# SRC_DIR = 脚本自身绝对目录（组件位置锚点 · BASH_SOURCE 自解析，正确保留）。
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT 解析优先级链（plugin-ready：去固定层数上推 · OQ-2 决议 A-混合）：
#   (a) 显式 --repo-root <path> 参数 ∨ WIKI_ENGINE_REPO_ROOT 环境变量（分发器注入点）
#   (b) git rev-parse --show-toplevel（锚 SRC_DIR · 在 git 仓库时）
#   (c) 回退 $PWD（沿用"在宿主仓库根运行"约定）
# 绝不回退固定 ../../.. 层数（否则等于没消除硬编码点②）。
REPO_ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root)    REPO_ROOT="${2:-}"; shift 2 ;;
    --repo-root=*)  REPO_ROOT="${1#--repo-root=}"; shift ;;
    *)              shift ;;
  esac
done
if [ -z "$REPO_ROOT" ] && [ -n "${WIKI_ENGINE_REPO_ROOT:-}" ]; then
  REPO_ROOT="$WIKI_ENGINE_REPO_ROOT"
fi
if [ -z "$REPO_ROOT" ]; then
  if git_root="$(git -C "$SRC_DIR" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$git_root" ]; then
    REPO_ROOT="$git_root"
  fi
fi
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$PWD"
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

# 1. 前置：python3（脚本纯标准库）；脚本执行位。
if ! command -v python3 >/dev/null 2>&1; then
  say "ERROR: PATH 上没有 python3（脚本仅用标准库，但需要解释器）。" >&2
  exit 1
fi
chmod +x "$SRC_DIR/bin/wiki-rescan" "$SRC_DIR/bin/wiki-lint" \
         "$SRC_DIR/bin/wiki-extract" "$SRC_DIR/bin/wiki-ingest-cheap"

# 2. 项目级 skill 注册（相对符号链接，仓库被整体移动也不断）。
#    链接目标按 SRC_DIR 相对 .claude/skills 的"实际相对深度"计算，不写死 ../../ 布局
#    （plugin 分发到非默认深度也正确）。realpath 缺 --relative-to 时回退 python relpath
#    （BusyBox/macOS 兼容）。
mkdir -p "$REPO_ROOT/.claude/skills"
link_target="$(realpath --relative-to="$REPO_ROOT/.claude/skills" "$SRC_DIR" 2>/dev/null)" \
  || link_target="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
       "$SRC_DIR" "$REPO_ROOT/.claude/skills")"
ln -sfn "$link_target" "$REPO_ROOT/.claude/skills/wiki-engine"

# 3. 自检：脚本必须能从安装后的路径运行。
if ! "$REPO_ROOT/.claude/skills/wiki-engine/bin/wiki-rescan" --help >/dev/null 2>&1; then
  say "ERROR: 经符号链接运行 wiki-rescan 失败。" >&2
  exit 1
fi
if ! "$REPO_ROOT/.claude/skills/wiki-engine/bin/wiki-lint" --help >/dev/null 2>&1; then
  say "ERROR: 经符号链接运行 wiki-lint 失败。" >&2
  exit 1
fi

say "Installed:"
say "  skill 链接 : $REPO_ROOT/.claude/skills/wiki-engine -> $link_target"
say ""
say "Next:"
say "  1. export DEEPSEEK_API_KEY=...   # 摄取会话用；不要写进任何文件"
say "  2. .harness/components/wiki-engine/bin/wiki-rescan --wiki wiki --init --source-dir <源目录>"
say "  3. 按 SKILL.md 五条工作流操作；每批结束独立运行 bin/wiki-lint"
say ""
say "Uninstall: rm \"$REPO_ROOT/.claude/skills/wiki-engine\""
