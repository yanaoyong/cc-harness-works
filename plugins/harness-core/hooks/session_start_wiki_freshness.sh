#!/usr/bin/env bash
# SessionStart 钩子（detect-only · 维护侧）：会话启动时编排既有 wiki-rescan（read-only）
# 检测项目文档 wiki（wiki/）相对源文档的 new/changed 未摄取 delta，仅 stderr 报计数提示，
# 引导维护者跑摄取批循环收敛欠摄债。落地 RM-2026-119 / ADR-010 定稿组合：
#   A3-SessionStart + B1-detect-only 起步 · 全程非阻塞 exit 0。
#
# == 命脉红线（本卡身份界定 · 防自相矛盾）==
# 本 hook 是**维护侧 hook**（动 wiki 内容新鲜度 · 不动 agent 工具选择），严守 C-A9（维护
# hook 须非阻塞 · exit 0 永不阻断 · 不进门禁 · 不拦 Read）。它**不是**被 codegraph dossier
# L6 硬数据证否的**消费侧强制 hook**（拦 Read 逼 agent 用 wiki → 绕路慢 3–4×，C-A1/O-A07 禁）。
# 两类 hook 作用对象正交：本 hook 只读检测 wiki 新鲜度 + stderr 提示，零拦截、零门禁、零 mutation。
#
# 设计原则（对齐 session_start_autosync.sh / session_start_autoflip.sh 三先例）：
#   守卫齐全才检测，否则静默退出 0，永不阻断会话。
# 短路顺序：①仓库根定位 → ②wiki/ 目录存在 → ③wiki/_meta/state.json 存在 → ④wiki-rescan bin
#           三级回退链定位（.harness/ 消费方安装态 → plugins/harness-core/ 本仓开发态 →
#           $CLAUDE_PLUGIN_ROOT/ plugin 包内直读 · 首个可读即用 · 全不命中静默 exit 0）
#           → 调 wiki-rescan --wiki wiki/（read-only）→ python3 解析 JSON 计数 → stderr 报。
# 所有提示走 stderr，统一前缀 [harness:wiki_freshness]；任何路径最终 exit 0。
#
# detect-only 起步（B1）：绝不调 wiki-ingest-cheap / 绝不写 wiki / 绝不 commit / 绝不 git add。
#   摄取（B2 · DeepSeek 出站 + wiki-lint 六门禁 + 矛盾裁决）作为可选异步/后台叠加路径，起步不上。
# 优雅降级（AC-119-e）：detect-only 本身零出站、不依赖 DEEPSEEK_API_KEY——任何路径都不因 key
#   缺失退非 0。
# corpus（OQ-3）：默认形参写死 --wiki wiki/，不触背景库 wiki-background/（R-015/OQ-A9 用户侧维护）。
# --all（OQ-2）：detect-only 起步不默认每次 --all（避免每会话启动全量 SHA256 拖墙钟），走默认
#   轻量 wiki-rescan（git diff 收窄 changed · new 靠 os.walk 免疫 git 假阴）。可选开关见下方注释。
#
# bash 3.2 兼容（NFR-2）：不使用 declare -A / 关联数组 / mapfile / readarray / bash4-only 语法。
set -uo pipefail

PREFIX="[harness:wiki_freshness]"

# 自定位仓库根；非 git / 定位失败 → 静默退出 0
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TOP" ] && exit 0
cd "$TOP" || exit 0

# 守卫①：wiki/ 产物目录存在（缺 → 静默退出 0，退化为 v1 纯纪律 WK-S 手动摄取 · AC-119-f）
[ -d "$TOP/wiki" ] || exit 0

# 守卫②：wiki/_meta/state.json 存在（wiki-rescan 检测依赖的既有 state · 只读不写）
[ -f "$TOP/wiki/_meta/state.json" ] || exit 0

# 守卫③：既有 wiki-rescan bin 三级回退链定位（编排既有 bin · 只调用不改 · C-A4 只加不改）
# 对齐 session_start_resident_contract.sh 先例：按序探测、首个可读即用（全部绝对路径拼接，
# 零相对路径）。第③级先判 CLAUDE_PLUGIN_ROOT 非空，防拼出 /components/… 根路径假路径
# （承 failure-record-001）。三级全不命中 → 静默 exit 0（有意偏离先例的 stderr 提示：
# 消费方安装态资产未落盘属正常态 fail-open，提示反成噪声 · spec AC-A2 留痕）。
RESCAN=""
if [ -r "$TOP/.harness/components/wiki-engine/bin/wiki-rescan" ]; then
  # 链①：消费方安装态
  RESCAN="$TOP/.harness/components/wiki-engine/bin/wiki-rescan"
elif [ -r "$TOP/plugins/harness-core/components/wiki-engine/bin/wiki-rescan" ]; then
  # 链②：本仓开发态
  RESCAN="$TOP/plugins/harness-core/components/wiki-engine/bin/wiki-rescan"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/components/wiki-engine/bin/wiki-rescan" ]; then
  # 链③：plugin 包内直读（先判 CLAUDE_PLUGIN_ROOT 非空）
  RESCAN="${CLAUDE_PLUGIN_ROOT}/components/wiki-engine/bin/wiki-rescan"
fi
[ -z "$RESCAN" ] && exit 0

# 可选 --all 开关（OQ-2 · 默认关闭）：HARNESS_WIKI_FRESHNESS_ALL=1 时走全量 SHA256 比对，
# 覆盖 git-diff 假阴窄缝（changed 一路 · git checkout/切分支后漏报）；默认走轻量 git-diff 收窄。
RESCAN_ALL_FLAG=""
if [ "${HARNESS_WIKI_FRESHNESS_ALL:-0}" = "1" ]; then
  RESCAN_ALL_FLAG="--all"
fi

# 恒做检测（read-only · 零出站）：调既有 wiki-rescan --wiki wiki/，stdout 是 JSON
# {"mode":...,"new":[...],"changed":[...],"deleted":[...]}。捕获 stdout 供 python3 解析。
rescan_out="$(python3 "$RESCAN" --wiki wiki/ $RESCAN_ALL_FLAG 2>/dev/null)"
rescan_rc=$?

# wiki-rescan 退非 0（state 异常 exit 5 / 参数错 exit 2 / 内部错）→ 提示后 exit 0（不阻断）
if [ "$rescan_rc" -ne 0 ]; then
  echo "$PREFIX wiki-rescan 检测失败（rc=$rescan_rc），跳过本次检测（不阻断会话）" >&2
  exit 0
fi

# python3 解析 JSON 提取 new/changed/deleted 计数（wiki-rescan 本身即 python3，已是检测路径
# 硬依赖；禁用 grep -c 数 JSON 数组行的脆弱解析）。解析失败 → 提示后 exit 0。
counts="$(printf '%s' "$rescan_out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("%d %d %d" % (len(d.get("new", [])), len(d.get("changed", [])), len(d.get("deleted", []))))
except Exception:
    sys.exit(1)
' 2>/dev/null)"
parse_rc=$?

if [ "$parse_rc" -ne 0 ] || [ -z "$counts" ]; then
  echo "$PREFIX wiki-rescan 输出解析失败，跳过本次检测（不阻断会话）" >&2
  exit 0
fi

# 拆分计数（bash 3.2 兼容 · 用位置参数而非数组）
set -- $counts
new_n="$1"
changed_n="$2"
deleted_n="$3"

# 报告（AC-119-b 新鲜度可观测）：有未摄取 delta → stderr 报计数 + 引导摄取；全 0 → wiki 新鲜。
if [ "$new_n" -gt 0 ] 2>/dev/null || [ "$changed_n" -gt 0 ] 2>/dev/null; then
  echo "$PREFIX wiki 未摄取 delta：new=$new_n changed=$changed_n（read-only 检测 · 跑 wiki-ingest 批循环摄取以收敛）" >&2
else
  echo "$PREFIX wiki 新鲜（无未摄取 delta · new=0 changed=0）" >&2
fi

# detect-only：不写、不 commit、不 push、不调 wiki-ingest-cheap —— 仅检测 + 提示。
# 永不阻断会话（C-A9 · exit 0 硬准则）
exit 0
