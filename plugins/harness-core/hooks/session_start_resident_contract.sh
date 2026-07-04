#!/usr/bin/env bash
# SessionStart 钩子：会话启动时注入常驻契约可重建子集（RM-140）。
# 设计原则：守卫齐全才注入，否则静默退出 0，永不阻断会话。
#
# 短路顺序：①仓库根定位 → ②注入源三级回退链定位 → stdout 注入 → 任何路径最终 exit 0。
# 所有提示走 stderr，统一前缀 [harness:resident_contract]；任何路径最终 exit 0。
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
