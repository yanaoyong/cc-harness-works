#!/usr/bin/env bash
# SessionEnd 钩子（opt-in · transcript 归档触发入口之一）：会话收尾时触发 transcript_archive.py sync，
# 把本机 ~/.claude/projects/<项目>/*.jsonl（+ subagents/workflows 附属目录）增量 lean 提取 + 落归档仓。
# 变更卡 feat-transcript-archive-20260717 · T5（触发入口：hook + cron）。
#
# == opt-in 语义（AC-5 · 未启用零动作）==
# 本 hook **不自动注册**（不入 hooks.json）——注册指引由启用 skill（T4）承载。仅在用户显式启用
# （状态目录下 config.json 存在且 "enabled": true）后才产生任何动作；未启用则静默 exit 0，
# 无输出、无落盘、无子进程调用。
#
# == 三入口同脚本（spec §2.1.7）==
# 手动命令 / cron / 本 SessionEnd hook 三入口复用同一 transcript_archive.py，路径口径与
# transcript_archive_cron.sample 一致。hook 触发**不推远端**（调 `sync` 不带 `--push`）——
# 推送留给 cron/手动显式 `sync --push`（Owner 冻结配置契约）。
#
# == worktree 免疫（spec R-4）==
# 关联提取纯离线读 JSONL（~/.claude/projects/…），不依赖运行时 hook 存活——即便本 hook 在
# worktree 下被杀（已知 UserPromptSubmit hook 族现象），后续任一入口（cron/手动）仍能补齐归档，
# 主路径不因单次 hook 失效丢证据。
#
# == fail-open 硬准则（hook 永不阻断会话收尾）==
# 恒 exit 0 全路径：config 缺失/未启用 → 静默 exit 0；python3 缺失/脚本三级回退均未命中/sync
# 非零退出 → 吞掉 + stderr 一行提示（前缀 [harness:transcript_archive]）后 exit 0。
# EXIT trap 兜底强制 exit 0，即便中途出现非预期错误也绝不以非零码阻断会话收尾。
# 并发安全由 transcript_archive.py sync 自带的归档仓级 flock 自理（本 hook 不理并发）。
#
# bash 3.2 兼容：不使用 declare -A / mapfile / readarray 等 bash4-only 语法。
set -euo pipefail
trap 'exit 0' EXIT

PREFIX="[harness:transcript_archive]"

# ── opt-in 门①：状态目录 + config.json 定位（Owner 冻结配置契约）──
# STATE_HOME = 环境变量 HARNESS_TRANSCRIPT_ARCHIVE_HOME，缺省 ~/.claude/harness-transcript-archive
STATE_HOME="${HARNESS_TRANSCRIPT_ARCHIVE_HOME:-$HOME/.claude/harness-transcript-archive}"
CONFIG="$STATE_HOME/config.json"

# config 缺失/不可读 → 静默 exit 0（opt-in 零动作 · 无任何输出/落盘 · AC-5）
[ -r "$CONFIG" ] || exit 0

# ── opt-in 门②：python3 可用性（无 python3 = 归档能力整体惰性 · 静默零动作，避免噪声）──
# 未启用态不应产生任何输出（AC-5）；判定 enabled 须先有 python3 解析 config，故 python3 缺失时
# 无法确知是否启用 → 保守按"能力不可用"静默退出（不打 stderr、不误报已启用会话的失败）。
command -v python3 >/dev/null 2>&1 || exit 0

# ── opt-in 门③：enabled 判定（config.json 存在且 "enabled": true 方启用）──
# 解析失败/字段缺失/非 true → enabled=0 → 静默 exit 0（fail-safe 到"未启用"，不 fail-open 到动作）
enabled="$(python3 -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
    print("1" if d.get("enabled") is True else "0")
except Exception:
    print("0")' "$CONFIG" 2>/dev/null || echo 0)"
[ "$enabled" = "1" ] || exit 0

# ══ 至此确认已启用 ══（以下路径失败均吞掉 + stderr 一行提示，仍 exit 0）

# ── 三级回退定位 transcript_archive.py（对齐 mirror_sync / wiki_freshness 先例）──
# 链①消费方安装态 → 链②本仓开发态 → 链③plugin 包内直读（先判 CLAUDE_PLUGIN_ROOT 非空防拼假路径）。
# 首个可读即用；全不命中 → stderr 一行 + exit 0。
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"

SCRIPT=""
if [ -n "$TOP" ] && [ -r "$TOP/.harness/scripts/transcript_archive.py" ]; then
  # 链①：消费方安装态（.harness/ 镜像）
  SCRIPT="$TOP/.harness/scripts/transcript_archive.py"
elif [ -n "$TOP" ] && [ -r "$TOP/plugins/harness-core/scripts/transcript_archive.py" ]; then
  # 链②：本仓开发态（权威源）
  SCRIPT="$TOP/plugins/harness-core/scripts/transcript_archive.py"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/scripts/transcript_archive.py" ]; then
  # 链③：plugin 包内直读（先判 CLAUDE_PLUGIN_ROOT 非空 · 承 failure-record-001 防拼 /scripts/… 假路径）
  SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/transcript_archive.py"
fi

if [ -z "$SCRIPT" ]; then
  echo "$PREFIX transcript_archive.py 三级回退均未命中，跳过归档（fail-open · 不阻断会话收尾）" >&2
  exit 0
fi

# ── 触发 sync（不带 --push · hook 触发不推远端）──
# stdout 丢弃（不污染会话输出）；sync 自身 stderr（flock skip 可观测 / cold_sync warning 等）透传；
# 非零退出吞掉 + 追加一行本 hook 提示。并发 contention 由 sync 内 flock 自理（第二实例干净 skip）。
if ! python3 "$SCRIPT" sync >/dev/null; then
  echo "$PREFIX transcript_archive.py sync 非零退出（fail-open 吞掉 · 不阻断会话收尾）" >&2
fi

exit 0
