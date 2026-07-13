#!/usr/bin/env bash
# flip_merged.sh —— 显式翻牌落库（fix-autoflip-oq3-propagation · 方案 A 动作③ · OQ-2）。
#
# 职责（R1 还债 · 合规路径）：把"PR 已合并进 main 但 summary 终态未翻"的变更卡，经
# branch off origin/main → 应用翻牌（总体状态→PASSED / 当前阶段→10 / 代码推送行回填 merge SHA）
# → commit → push → gh pr create 合规落库。**绝不直推 main**（守 DF-007/DF-008）。
#
# 与 autoflip hook 的分工：hook（detect-only）只 stderr 提示；本脚本是显式人工动作，把翻牌
# mutation 经 PR 合规传播到 origin/main，根除原 hook 直 commit 本地 main 的分叉问题（D1/D2）。
#
# == 角色退化（chore-flip-stage10-premerge · DF-013 · OQ-4 决议）==
# 自 DF-013 起，summary 终态翻牌的**主路径已前移到阶段10 分支内**——卡在 HITL-5 授权后、merge
#   前于变更分支翻牌，随 PR 合并进 main（main 上正常路径的卡天然 PASSED）。本脚本因此退化为
#   **兜底**：仅对**历史遗留 / 漏翻**卡（已合并但 summary 终态未翻）做合规批量翻牌（branch off
#   origin/main → 翻状态/阶段 + 回填 merge SHA → push → PR）。状态翻牌 + SHA 回填的行为零变化
#   （OQ-4 决议），本次仅头部注释文档化退化角色；仍走 branch→PR 合规路径、绝不直推 main。
#
# 用法:
#   bash .harness/scripts/flip_merged.sh [YYYYMMDD]
#     可选位参 = 分支日期后缀（缺省用 date '+%Y%m%d'）。分支名 change/autoflip-flips-<YYYYMMDD>。
#
# 守卫（fail-open · 永不破坏仓库状态）：
#   - 非 git / 定位失败 / lib 缺 → 提示并 exit 0。
#   - 当前分支非 main 或工作树脏 → 提示并 exit 0（不在脏树/非 main 上切分支翻牌）。
#   - 无待翻牌卡 → 提示并 exit 0。
#   - gh / 网络缺失 → 分支已建 + commit 已落，提示"请手动开 PR"、exit 0。
#
# bash 3.2 兼容：不使用 declare -A / mapfile / readarray。
set -uo pipefail

PREFIX="[harness:flip-merged]"

# --- 仓库根定位 ---
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TOP" ] && { echo "$PREFIX 非 git 仓库，跳过" >&2; exit 0; }
cd "$TOP" || { echo "$PREFIX 无法 cd 仓库根，跳过" >&2; exit 0; }

# --- FR-5 判定单点 ---
LIB="$TOP/.harness/scripts/lib/merged_detect.sh"
[ -r "$LIB" ] && . "$LIB" || { echo "$PREFIX 缺 merged_detect.sh，跳过" >&2; exit 0; }

# --- 守卫：当前分支 == main 且工作树干净 ---
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$branch" != "main" ]; then
  echo "$PREFIX 当前分支为 '$branch'（非 main），请先 checkout main 再运行；跳过" >&2
  exit 0
fi
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "$PREFIX 工作树有未提交改动，请先提交/暂存再运行；跳过" >&2
  exit 0
fi

CHANGES_DIR="$TOP/.harness/changes"
[ -d "$CHANGES_DIR" ] || { echo "$PREFIX 无 .harness/changes，跳过" >&2; exit 0; }

DATE_SUFFIX="${1:-$(date '+%Y%m%d')}"
BRANCH="change/autoflip-flips-$DATE_SUFFIX"

# --- 第一遍：收集待翻牌卡（card_dir <tab> short_sha）· 不写 ---
PENDING=""
for summary in "$CHANGES_DIR"/*/summary.md; do
  [ -f "$summary" ] || continue
  card_dir="$(basename "$(dirname "$summary")")"
  [ "$card_dir" = "_TEMPLATE" ] && continue

  status_line="$(grep -E '^\| *总体状态 *\|' "$summary" 2>/dev/null | head -1 || true)"
  [ -z "$status_line" ] && continue
  status_val="$(printf '%s\n' "$status_line" | awk -F'|' '{print $3}' | sed 's/\*\*//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ "$status_val" = "PASSED" ] && continue

  short_sha="$(merged_detect_sha "$card_dir" || true)"
  [ -z "$short_sha" ] && continue

  PENDING="$PENDING$card_dir	$short_sha
"
done

if [ -z "$PENDING" ]; then
  echo "$PREFIX 无待翻牌卡（所有已合并卡 summary 终态均已 PASSED），跳过" >&2
  exit 0
fi

count="$(printf '%s' "$PENDING" | grep -c . || true)"
echo "$PREFIX 发现 $count 张待翻牌卡，开始合规落库（分支 $BRANCH · off origin/main）" >&2

# --- 从 origin/main 建分支（合规起点 · 不在本地 main 上 commit）---
git fetch origin main 2>/dev/null || echo "$PREFIX fetch origin 失败，将基于本地 main 建分支" >&2
BASE="origin/main"
git rev-parse --verify "origin/main" >/dev/null 2>&1 || BASE="main"

if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  echo "$PREFIX 分支 $BRANCH 已存在，请删除或换日期后缀后重试；跳过" >&2
  exit 0
fi
git checkout -b "$BRANCH" "$BASE" 2>/dev/null || {
  echo "$PREFIX 无法从 $BASE 建分支 $BRANCH，跳过" >&2
  exit 0
}

# --- 在分支上逐张应用翻牌（行级 sed · 复用 autoflip 原 FR-6 写法）---
flipped=0
printf '%s' "$PENDING" | while IFS='	' read -r card_dir short_sha; do
  [ -n "$card_dir" ] || continue
  summary="$CHANGES_DIR/$card_dir/summary.md"
  [ -f "$summary" ] || continue

  tmp="$summary.flip.tmp.$$"
  # ① 总体状态 → PASSED；② 当前阶段 → 10（行级 sed · 非整篇重写）
  sed \
    -e 's/^\(| *总体状态 *|\)[^|]*\(|.*\)$/\1 PASSED \2/' \
    -e 's/^\(| *当前阶段 *|\)[^|]*\(|.*\)$/\1 10 \2/' \
    "$summary" > "$tmp" 2>/dev/null || { rm -f "$tmp"; continue; }

  # ③ 回填 merge SHA 到「代码推送」阶段记录行最后单元格（语义锚点 · 幂等：未含 merged 才追加）
  if grep -Eq '代码推送' "$tmp" 2>/dev/null && ! grep -E '代码推送' "$tmp" | grep -q "merged $short_sha"; then
    sed -e "/代码推送/ s/ *|\([[:space:]]*\)\$/ · merged $short_sha |\1/" "$tmp" > "$tmp.2" 2>/dev/null \
      && mv "$tmp.2" "$tmp" 2>/dev/null || { rm -f "$tmp" "$tmp.2"; continue; }
  fi

  mv "$tmp" "$summary" 2>/dev/null || { rm -f "$tmp"; continue; }
  git add "$summary" 2>/dev/null || true
done

# --- commit（子 shell 内 flipped 计数不外传 · 改用 git diff --cached 判有无暂存）---
if git diff --cached --quiet 2>/dev/null; then
  echo "$PREFIX 无翻牌改动被暂存（可能已幂等），分支 $BRANCH 已建但空；请自查" >&2
  exit 0
fi

git commit -q \
  -m "chore(autoflip): flip merged cards summary→PASSED [flip-merged]" \
  -m "$count 张已合并卡终态落库（显式 flip_merged.sh · branch off $BASE · 经 PR 合规传播）" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" \
  2>/dev/null || { echo "$PREFIX commit 失败，跳过" >&2; exit 0; }

echo "$PREFIX 已在分支 $BRANCH 提交翻牌（绝不直推 main）" >&2

# --- push + 开 PR（fail-open：gh/网络缺失则提示手动）---
if git push -u origin "$BRANCH" 2>/dev/null; then
  echo "$PREFIX 已 push $BRANCH 到 origin" >&2
  if command -v gh >/dev/null 2>&1; then
    if gh pr create --base main --head "$BRANCH" \
        --title "chore(autoflip): flip $count merged cards summary→PASSED" \
        --body "显式 flip_merged.sh 落库 $count 张已合并卡终态（总体状态→PASSED / 当前阶段→10 / 回填 merge SHA）。off $BASE · 经 PR 合规传播（不直推 main）。" \
        2>/dev/null; then
      echo "$PREFIX 已开 PR（请走 HITL 审查 + merge 授权）" >&2
    else
      echo "$PREFIX gh pr create 失败：分支已 push，请手动开 PR（base main · head $BRANCH）" >&2
    fi
  else
    echo "$PREFIX 无 gh：分支已 push，请手动开 PR（base main · head $BRANCH）" >&2
  fi
else
  echo "$PREFIX push 失败（网络/权限）：分支 $BRANCH + commit 已就绪本地，请手动 push 并开 PR" >&2
fi

# 永不阻断
exit 0
