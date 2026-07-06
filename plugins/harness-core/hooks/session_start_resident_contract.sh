#!/usr/bin/env bash
# SessionStart 钩子：会话启动时注入常驻契约可重建子集（RM-140）。
# 设计原则：守卫齐全才注入，否则静默退出 0，永不阻断会话。
#
# 短路顺序：①仓库根定位 → ①.5 CLAUDE.md @import 常驻检测（跳过守卫 + 首会话桥接）
#          → ②注入源三级回退链定位 → stdout 注入 → 任何路径最终 exit 0。
# 所有提示走 stderr，统一前缀 [harness:resident_contract]；任何路径最终 exit 0。
#
# 守卫①.5（feat-claudemd-full-restore-20260706 · AC-3/AC-3b）：
#   $TOP/CLAUDE.md 若已含 application-owner.md 的 @import（双串枚举 · grep -qF 字面匹配防 BRE 假阳性）
#   → 契约已随 CLAUDE.md 常驻，注入即双份加载，默认跳过注入（stderr 说明 + exit 0）。
#   首会话桥接例外：$TOP/.harness/state/.claudemd_restored_pending 哨兵存在（复原相位当轮由 T1 落盘）
#   → 删哨兵、照常注入——复原当轮写入的 CLAUDE.md 要下会话才被加载，本轮仍需注入防契约真空。
#   哨兵异常残留自愈：见哨兵即"删哨兵+注入"，最多多注入一个会话即收敛。
#   排序安全性（code_review_v1 M-1 附注）：本仓 .claude/settings.json 中本 hook 排在 session-start.sh
#   之前（与 hooks.json 反序 · 有意设计），守卫①.5 语义下仍安全——复原当轮 CLAUDE.md 尚缺失
#   → 不命中 → 照常注入无真空；次会话命中跳过，至多多注入一会话（与哨兵残留自愈同构）。
#   STATE_DIR 口径（code_review_v1 M-2）：与写端 session-start.sh 一致，含 HARNESS_STATE_DIR 逃生口（ADR-016）。
#
# 注入源三级回退链（fix-resident-contract-hook-consistency-20260702 · AC-1）：
#   ① $TOP/.harness/skills/setup/resident_contract_injectable.md（消费方安装态 · 脚手架已落盘）
#   ② $TOP/plugins/harness-core/skills/setup/resident_contract_injectable.md（本仓开发态）
#   ③ $CLAUDE_PLUGIN_ROOT/skills/setup/resident_contract_injectable.md（plugin 包内直读 · 兜住首会话空窗；
#      CLAUDE_PLUGIN_ROOT 为空/未设时跳过本级，防拼出根路径假路径 · 承 failure-record-001）
#   首个可读即用；三级全不可读 → stderr 提示后跳过注入。
#
# 职责收敛（D-6 · 落盘收敛）：_TEMPLATE 等脚手架落盘职责唯一归 session-start.sh，本 hook 不再承担。
# bash 3.2 兼容：不使用 declare -A / 关联数组 / mapfile / readarray / bash4-only 语法。
set -uo pipefail

PREFIX_CONTRACT="[harness:resident_contract]"

# 守卫① 自定位仓库根；非 git / 定位失败 → 静默退出 0
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TOP" ] && exit 0
cd "$TOP" || exit 0

# 守卫①.5 CLAUDE.md @import 常驻检测（feat-claudemd-full-restore-20260706）
# 双串枚举：消费方安装态 @.harness/... / 本仓开发态 @plugins/harness-core/...（漏检后者会导致本仓双份加载）
# grep -qF 字面匹配（防 BRE 通配假阳性）；文件不存在 = 不命中，照常注入。
# STATE_DIR 与写端 session-start.sh 同口径：HARNESS_STATE_DIR 逃生口贯通读写两端（M-2 · ADR-016）。
STATE_DIR="${HARNESS_STATE_DIR:-$TOP/.harness/state}"
RESTORE_SENTINEL="$STATE_DIR/.claudemd_restored_pending"
if [ -f "$TOP/CLAUDE.md" ] \
  && { grep -qF '@.harness/agents/application-owner.md' "$TOP/CLAUDE.md" 2>/dev/null \
       || grep -qF '@plugins/harness-core/agents/application-owner.md' "$TOP/CLAUDE.md" 2>/dev/null; }; then
  if [ -f "$RESTORE_SENTINEL" ]; then
    # 首会话桥接：CLAUDE.md 刚复原、本会话启动时尚未加载 @import → 删哨兵、照常注入（防契约真空；残留自愈）
    rm -f "$RESTORE_SENTINEL" 2>/dev/null
    echo "$PREFIX_CONTRACT 检测到 .claudemd_restored_pending 哨兵：CLAUDE.md 刚复原、本会话未加载 @import，桥接注入一次（哨兵已清）" >&2
  else
    echo "$PREFIX_CONTRACT CLAUDE.md @import 已常驻（application-owner.md 引用命中），跳过注入" >&2
    exit 0
  fi
fi

# ============================================================
# 常驻契约注入（RM-140）
# ============================================================

# 守卫② 注入源三级回退链：按序探测、首个可读即用（全部绝对路径拼接，零相对路径）
INJECTABLE=""
if [ -r "$TOP/.harness/skills/setup/resident_contract_injectable.md" ]; then
  # 链①：消费方安装态（session-start.sh 脚手架已落盘）
  INJECTABLE="$TOP/.harness/skills/setup/resident_contract_injectable.md"
elif [ -r "$TOP/plugins/harness-core/skills/setup/resident_contract_injectable.md" ]; then
  # 链②：本仓开发态
  INJECTABLE="$TOP/plugins/harness-core/skills/setup/resident_contract_injectable.md"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/skills/setup/resident_contract_injectable.md" ]; then
  # 链③：plugin 包内直读（先判 CLAUDE_PLUGIN_ROOT 非空，防 /skills/… 假路径）
  INJECTABLE="${CLAUDE_PLUGIN_ROOT}/skills/setup/resident_contract_injectable.md"
fi

if [ -z "$INJECTABLE" ]; then
  echo "$PREFIX_CONTRACT 注入源文件不存在或不可读（三级回退链均未命中），跳过注入（不影响会话）" >&2
else
  # 成功路径：读取注入源文件，完整内容输出到 stdout
  if cat "$INJECTABLE" 2>/dev/null; then
    echo "$PREFIX_CONTRACT 常驻契约已注入（$(wc -l < "$INJECTABLE" 2>/dev/null || echo 0) 行 · 源=$INJECTABLE）" >&2
  else
    echo "$PREFIX_CONTRACT 读取注入源文件失败，跳过注入（不影响会话）" >&2
  fi
fi

# 永不阻断
exit 0
