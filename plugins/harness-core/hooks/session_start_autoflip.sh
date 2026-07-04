#!/usr/bin/env bash
# SessionStart 钩子（detect-only）：会话启动时，检测"PR 已合并进 main 但 summary 终态未翻"的
# 变更卡，仅 stderr 提示有 N 张待翻牌、引导人运行 flip_merged.sh 落库。
#
# == 设计变更（fix-autoflip-oq3-propagation · 方案 A · OQ-3 修订）==
# 原 hook（PR #52）翻牌后 `git commit` 到本地 main，导致本地 main 分叉（D1 无合规推送路径 /
# D2 破 autosync ff 同步）。本卡改 detect-only：
#   - 移除 FR-6 sed 写入 + FR-8 git commit —— 不再向本地 main 写任何东西（根除 D1/D2）。
#   - 保留 FR-5 检测（改为 source lib/merged_detect.sh · 单点判定防双源漂移）+ 守卫三连 + FR-9 提示。
#   - R4 消噪职责移交 list_flows.sh --active（检测层排除已合并卡 · 零 mutation 零分叉）。
#   - R1 终态落库职责移交显式脚本 flip_merged.sh（branch off origin/main → 翻牌 → push → PR · 合规）。
#
# 设计原则（保留 NFR-1..5）：守卫齐全才检测，否则静默退出 0，永不阻断会话。
# 短路顺序：①仓库根定位 → ②分支==main → ③工作树干净 → 候选集（总体状态!=PASSED）→
#           per-card merged 判定（merged_detect.sh）→ stderr 计数提示（不写、不 commit、不 push）。
# 所有提示走 stderr，统一前缀 [harness:autoflip]；任何路径最终 exit 0。
#
# bash 3.2 兼容（NFR-2）：不使用 declare -A / 关联数组 / mapfile / readarray / bash4-only 语法。
# 无 gh / 网络硬依赖（NFR-3）：纯 git + grep/coreutils；merged 真相由前序 autosync 把本地 main
#   ff 同步到最新后，在本地 main 历史上判定。
# RISK-2 假设（squash/rebase 无 merge commit）：判定依赖 DF-008 强制 merge commit 策略；
#   若改 squash/rebase 则 git log --merges 找不到候选 → 退化为"不报"（保守、永不误报）。
#
# == 角色退化（chore-flip-stage10-premerge · DF-013 · OQ-1 决议）==
# 自 DF-013 起，summary 终态翻牌的**主路径已前移到阶段10 分支内**——HITL-5 授权后、merge 前
#   在变更分支上翻牌（总体状态→PASSED / 当前阶段→10 / merge SHA 占位），随 PR 合并进 main，
#   使 main 上正常走完阶段10 的卡天然 PASSED。本 hook 因此退化为**安全网**：候选集（总体状态
#   != PASSED）对正常路径的卡不再命中，hook 仅检测**漏翻 / 历史遗留**卡（已合并但 summary 终态
#   未翻 PASSED）并 stderr 提示。
# 行为零变化（OQ-1 决议）：检测逻辑 / 候选集判定 / merged_detect 调用 / stderr 文案 / exit
#   全部不改——本次仅头部注释文档化退化角色。**不追 merge SHA 占位**（OQ-2 占位即合规终态，
#   `{{merge SHA 待回填}}` 为纯人读约定、无机械消费方，追占位是噪声）。仍 detect-only：不写、
#   不 commit、不 push。
set -uo pipefail

PREFIX="[harness:autoflip]"

# FR-1 自定位仓库根；非 git / 定位失败 → 静默退出 0
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TOP" ] && exit 0
cd "$TOP" || exit 0

# FR-5 判定单点（lib/merged_detect.sh · 三处共享 · 防双源漂移）
LIB="$TOP/.harness/scripts/lib/merged_detect.sh"
[ -r "$LIB" ] && . "$LIB" || exit 0

# FR-2 守卫①：当前分支必须 == main（detached HEAD 返回 HEAD ≠ main，自然被拦截）
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[ "$branch" = "main" ] || exit 0

# FR-3 守卫②：工作树必须干净（不在用户有未提交改动时检测，与原口径一致）
[ -z "$(git status --porcelain 2>/dev/null)" ] || exit 0

CHANGES_DIR="$TOP/.harness/changes"
[ -d "$CHANGES_DIR" ] || exit 0

pending_count=0
pending_dirs=""

# FR-4 候选集：扫 .harness/changes/*/summary.md，取「总体状态」!= PASSED 的卡。
# 只在候选小集上工作（NFR-4）。字段行形如 `| 总体状态 | IN_PROGRESS |`，值可能含 ** 修饰需容错。
for summary in "$CHANGES_DIR"/*/summary.md; do
  [ -f "$summary" ] || continue

  card_dir="$(basename "$(dirname "$summary")")"
  # 跳过模板目录
  [ "$card_dir" = "_TEMPLATE" ] && continue

  # 提取「总体状态」表格行的值（anchor 到表格行首，避开正文中提及"总体状态"的散行）；
  # 去掉 ** 修饰与首尾空白后比较。
  status_line="$(grep -E '^\| *总体状态 *\|' "$summary" 2>/dev/null | head -1 || true)"
  [ -z "$status_line" ] && continue
  status_val="$(printf '%s\n' "$status_line" | awk -F'|' '{print $3}' | sed 's/\*\*//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"

  # FR-7 幂等：已 PASSED 跳过
  [ "$status_val" = "PASSED" ] && continue

  # FR-5 merged 判定（单点 · merged_detect.sh）：命中输出短 SHA 返回 0，未命中返回非 0。
  short_sha="$(merged_detect_sha "$card_dir" || true)"
  [ -z "$short_sha" ] && continue

  # detect-only：不写、不 commit、不 push —— 仅累计提示。
  echo "$PREFIX $card_dir 已合并待翻牌 (merge $short_sha · ${status_val:-IN_PROGRESS})" >&2
  pending_count=$((pending_count + 1))
  if [ -z "$pending_dirs" ]; then
    pending_dirs="$card_dir"
  else
    pending_dirs="$pending_dirs, $card_dir"
  fi
done

# FR-9 观测：有待翻牌卡时引导运行显式 flip 脚本落库（合规走 branch→PR · 不直推 main）。
if [ "$pending_count" -gt 0 ]; then
  echo "$PREFIX ${pending_count} 张卡已合并待翻牌（${pending_dirs}），运行 bash .harness/scripts/flip_merged.sh 落库" >&2
fi

# FR-10 永不阻断
exit 0
