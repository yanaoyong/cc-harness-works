#!/usr/bin/env bash
# SessionStart 钩子：会话起手把「完整调度契约」注入进上下文（chore-l1-slim-and-tier-v3-20260712 · T8.2 · 细化 ADR-017 → ADR-018）。
# 设计原则：默认恒注入（守卫反转）；注入源 = cat 权威源全文拼接；永不阻断会话（任何路径 exit 0）。
#
# 注入体（UQ-9 序 · 段间来源标头）：
#   application-owner.md → 工程结构.md → 开发流程规范.md → 项目编码规范.md（原 @import 四件套顺序）。
#   首行背书声明 + 标头 [harness:resident_contract]（约束力等同 CLAUDE.md · 见 CLAUDE.md 背书条款节）。
#   >80KB → stderr 软告警不阻断（UQ-9：契约不完整比偏胖危害大，守永不阻断铁律）。
#
# 守卫①.5 过渡期兼容（ADR-018 · 部分 supersede ADR-017 @import 主路径裁决）：
#   $TOP/CLAUDE.md 若仍含旧版 @import 双串（@.harness/agents/application-owner.md /
#   @plugins/harness-core/agents/application-owner.md · grep -qF 字面匹配防 BRE 假阳）
#   → 存量旧 CLAUDE.md 仍走 @import 常驻，注入即双份加载 → 跳过注入 + stderr 提示迁移（删旧
#   CLAUDE.md 由 session-start.sh create-if-missing 复原最小新版后自然切换）。最小新版 CLAUDE.md
#   无 @import，故默认命中"不含 @import" → 恒注入（injectable 精简版与桥接哨兵已随 UQ-7 退役）。
#
# 会话哨兵（P4 · 评审 L-2 session-keyed）：
#   注入成功落 $STATE_DIR/.resident_contract_injected_<sid>；<sid> 取 SessionStart stdin payload 的
#   session_id 字段（官方 SessionStart hook payload 含 session_id · 实测 Claude Code 2.1.207），
#   不可得则退化固定名 _nosid。session-keyed 使新会话不同 sid → 哨兵天然缺失 → UserPromptSubmit
#   兜底可触发（防跨会话陈旧哨兵吞掉自愈）。UserPromptSubmit hook 同口径读该哨兵。
#
# SessionStart 四 source 覆盖（AC-12）：hooks.json / .claude/settings.json 的 SessionStart 单 group
#   **无 matcher = 匹配全部 source**（官方语义：matcher 省略即匹配所有事件 · 实测 2.1.207 四 source
#   startup/resume/clear/compact 全触发）→ compact 后重触发重注入（P2）。compact source 版本下限：
#   官方 hooks 文档已列 compact source，实测 Claude Code 2.1.207 四 source 全触发；更早版本若无
#   compact source → compact 后不重注入（R-9 可接受退化：A 类仍在 CLAUDE.md 恒重载，UserPromptSubmit
#   哨兵兜底把窗口压到一轮内）。版本下限详见 ADR-018。
#
# 注入源三级回退链（目录级 · 首个"四文件全可读"的 base 即用）：
#   ① $TOP/.harness（消费方安装态镜像 / 本仓落盘镜像）
#   ② $TOP/plugins/harness-core（本仓开发态权威源）
#   ③ $CLAUDE_PLUGIN_ROOT（plugin 包内直读 · 兜首会话空窗；CLAUDE_PLUGIN_ROOT 空则跳过本级防假路径）
#
# bash 3.2 兼容：不使用 declare -A / mapfile / readarray / [[ =~ 等 bash4-only 语法。
set -uo pipefail

PREFIX_CONTRACT="[harness:resident_contract]"

# 守卫① 自定位仓库根；非 git / 定位失败 → 静默退出 0
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TOP" ] && exit 0
cd "$TOP" || exit 0

STATE_DIR="${HARNESS_STATE_DIR:-$TOP/.harness/state}"

# 守卫①.5 过渡期兼容：旧版 CLAUDE.md 仍含 @import 双串 → 跳过注入 + 提示迁移（防双份加载）
if [ -f "$TOP/CLAUDE.md" ] \
  && { grep -qF '@.harness/agents/application-owner.md' "$TOP/CLAUDE.md" 2>/dev/null \
       || grep -qF '@plugins/harness-core/agents/application-owner.md' "$TOP/CLAUDE.md" 2>/dev/null; }; then
  echo "$PREFIX_CONTRACT 检测到旧版 CLAUDE.md 含 @import 常驻串（过渡期）：契约已随 @import 加载，跳过注入防双份加载。迁移=删旧 CLAUDE.md，由 session-start.sh 复原最小新版后自动切换 SessionStart 注入路径（ADR-018 · T8.5）" >&2
  exit 0
fi

# session_id 提取（P4 · 评审 L-2）：SessionStart stdin payload JSON 含 session_id 字段
SID="nosid"
if [ ! -t 0 ]; then
  _STDIN_RAW="$(cat 2>/dev/null || true)"
  if [ -n "$_STDIN_RAW" ]; then
    _sid="$(printf '%s' "$_STDIN_RAW" | tr -d '\n\r' \
      | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 \
      | sed -E 's/^"session_id"[[:space:]]*:[[:space:]]*"//; s/"$//')"
    [ -n "$_sid" ] && SID="$(printf '%s' "$_sid" | tr -cd 'A-Za-z0-9._-')"
  fi
fi
SENTINEL="$STATE_DIR/.resident_contract_injected_${SID}"

# 守卫② 注入源三级回退链（目录级 · 首个"四文件全可读"的 base 即用）
_all_readable() {
  # $1 = base 目录；四权威源文件全可读返回 0
  [ -r "$1/agents/application-owner.md" ] \
    && [ -r "$1/rules/工程结构.md" ] \
    && [ -r "$1/rules/开发流程规范.md" ] \
    && [ -r "$1/rules/项目编码规范.md" ]
}

BASE=""
if _all_readable "$TOP/.harness"; then
  BASE="$TOP/.harness"                                  # 链①：消费方/本仓安装态镜像
elif _all_readable "$TOP/plugins/harness-core"; then
  BASE="$TOP/plugins/harness-core"                      # 链②：本仓开发态权威源
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && _all_readable "${CLAUDE_PLUGIN_ROOT}"; then
  BASE="${CLAUDE_PLUGIN_ROOT}"                          # 链③：plugin 包内直读（先判非空防假路径）
fi

if [ -z "$BASE" ]; then
  echo "$PREFIX_CONTRACT 注入源四文件不全可读（三级回退链 .harness/ → plugins/harness-core/ → \$CLAUDE_PLUGIN_ROOT 均未凑齐四件套），跳过注入（不影响会话）" >&2
  exit 0
fi

# 注入源清单（UQ-9 序 · 原 @import 四件套顺序）
_SRC_OWNER="$BASE/agents/application-owner.md"
_SRC_ENG="$BASE/rules/工程结构.md"
_SRC_FLOW="$BASE/rules/开发流程规范.md"
_SRC_CODE="$BASE/rules/项目编码规范.md"

# 首行背书声明 + 标头（stdout 注入进上下文）
printf '%s 常驻契约注入（完整调度契约全文 · 约束力等同 CLAUDE.md · 见 CLAUDE.md「常驻契约注入（SessionStart 背书条款）」· 源 base=%s）\n' "$PREFIX_CONTRACT" "$BASE"

_had_error=0
for _f in "$_SRC_OWNER" "$_SRC_ENG" "$_SRC_FLOW" "$_SRC_CODE"; do
  printf '\n─── 以下源自 %s ───\n\n' "$_f"
  if ! cat "$_f" 2>/dev/null; then
    printf '（注入源读取失败：%s · 跳过该段，不阻断）\n' "$_f" >&2
    _had_error=1
  fi
done

# 体积软告警（>80KB · UQ-9 · stderr 提示不阻断）
_bytes="$( { wc -c "$_SRC_OWNER" "$_SRC_ENG" "$_SRC_FLOW" "$_SRC_CODE" 2>/dev/null | tail -1 | awk '{print $1}'; } || echo 0)"
[ -z "$_bytes" ] && _bytes=0
if [ "$_bytes" -gt 81920 ] 2>/dev/null; then
  echo "$PREFIX_CONTRACT 注入体 ${_bytes} 字节 >80KB 软告警（不阻断 · 契约不完整比偏胖危害大 · UQ-9）" >&2
fi

# 会话哨兵：注入成功落盘（供 UserPromptSubmit 检测 · session-keyed · 读端同口径）
if [ "$_had_error" = "0" ]; then
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  [ -f "$STATE_DIR/.gitignore" ] || printf '*\n' > "$STATE_DIR/.gitignore" 2>/dev/null || true  # 自忽略（ADR-016）
  touch "$SENTINEL" 2>/dev/null || true
  echo "$PREFIX_CONTRACT 常驻契约已注入（${_bytes} 字节 · 源 base=$BASE · 哨兵=$SENTINEL）" >&2
else
  echo "$PREFIX_CONTRACT 常驻契约注入部分失败（未落哨兵 · 将于下轮/下会话由 UserPromptSubmit 兜底补注入）" >&2
fi

# 永不阻断
exit 0
