#!/usr/bin/env bash
# Stop 钩子（B2 auto-ingest 触发接线 · feat-wiki-auto-ingest-b2 · U1 定稿）：会话结束时
# fire-and-forget 后台启动 wiki-auto-ingest 编排，**不阻塞 Stop 退出**。落地 ADR-010 B2：
#   摄取只走异步/后台叠加路径（不压关键路径）· key 缺失/守卫不全优雅降级回退 B1（静默跳过）。
#
# == 命脉红线（守 ADR-010 三边界 + ADR-005 旁路）==
# 本 hook 是**维护侧 hook**（动 wiki 内容新鲜度 · 不动 agent 工具选择）：
#   ① 非阻塞：立即 exit 0，绝不阻断会话 Stop（摄取全程在后台跨回合持久进程内跑）。
#   ② 只后台异步：nohup/setsid detach 启后台进程 · 日志落文件（wiki/_meta/auto-ingest.log）
#      不刷会话 · 主脚本一 fire 即返回 exit 0（memory K4：长任务须持久后台、别塞进会 return 的路径）。
#   ③ 守卫不全 / key 缺 → 静默跳过（降级 B1 · detect-only 由 SessionStart freshness hook 承载）。
#   ④ opt-in 安全阀（默认关）：仅当显式 WIKI_ENGINE_AUTO_INGEST=1 才启后台摄取；未设/非 1 →
#      静默 exit 0（杜绝环境有 key 即每次会话结束 live-fire 失控摄取+commit · 阶段7 缺陷②修复）。
# 本 hook 不检测/不摄取/不写 wiki——只做「opt-in 开 + 守卫齐全 + key 就绪 → detach 后台编排 → exit 0」。
#
# 设计对齐 session_start_wiki_freshness.sh（三级 bin 回退链 / 全路径 exit 0 / bash3.2 兼容）
# 与 stop_progress_check.sh（Stop 体例 · set -uo pipefail 无 -e · 自定位 · 容错 exit 0）。
# 明确不加 -e：hook 须容错不中途中止、任何路径最终 exit 0。
set -uo pipefail

PREFIX="[harness:wiki_autoingest]"

# ---- opt-in 安全阀（默认关 · 杜绝环境有 key 即每次会话结束 live-fire 失控摄取）----
# 仅当显式 WIKI_ENGINE_AUTO_INGEST=1 才启自动后台摄取；未设/非 1 → 静默 exit 0（降级 B1）。
# 手动 CLI（wiki-auto-ingest --dry-run/无参）不读该门（显式人意图不受限）。
[ "${WIKI_ENGINE_AUTO_INGEST:-0}" = "1" ] || exit 0

# ---- 自定位仓库根；非 git / 定位失败 → 静默 exit 0 ----
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TOP" ] && exit 0
cd "$TOP" || exit 0

# ---- 守卫①②：wiki/ 与 state.json 存在（缺 → 静默 exit 0） ----
[ -d "$TOP/wiki" ] || exit 0
[ -f "$TOP/wiki/_meta/state.json" ] || exit 0

# ---- 守卫③：wiki-auto-ingest bin 三级回退链定位（消费方安装态 → 本仓开发态 → plugin 包内） ----
AUTOINGEST=""
if [ -r "$TOP/.harness/components/wiki-engine/bin/wiki-auto-ingest" ]; then
  AUTOINGEST="$TOP/.harness/components/wiki-engine/bin/wiki-auto-ingest"
elif [ -r "$TOP/plugins/harness-core/components/wiki-engine/bin/wiki-auto-ingest" ]; then
  AUTOINGEST="$TOP/plugins/harness-core/components/wiki-engine/bin/wiki-auto-ingest"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/components/wiki-engine/bin/wiki-auto-ingest" ]; then
  AUTOINGEST="${CLAUDE_PLUGIN_ROOT}/components/wiki-engine/bin/wiki-auto-ingest"
fi
[ -z "$AUTOINGEST" ] && exit 0

# ---- 守卫④：key 就绪（env 有 DEEPSEEK_API_KEY 或组件根 wiki-ingest.env 存在）。
#      均无 → 静默跳过（降级 B1 · 避免无谓后台唤醒；auto-ingest 自身亦二次守卫）。 ----
KEYFILE="$(dirname "$(dirname "$AUTOINGEST")")/wiki-ingest.env"
if [ -z "${DEEPSEEK_API_KEY:-}" ] && [ ! -f "$KEYFILE" ]; then
  exit 0
fi

# ---- 后台 detach 启动 auto-ingest（跨回合持久 · 日志落文件不刷会话）→ 立即 exit 0 ----
# setsid 优先（脱离会话进程组、Stop 退出后仍存活）；无 setsid 回退 nohup + & + </dev/null。
LOG="$TOP/wiki/_meta/auto-ingest.log"
if command -v setsid >/dev/null 2>&1; then
  setsid bash "$AUTOINGEST" >>"$LOG" 2>&1 </dev/null &
else
  nohup bash "$AUTOINGEST" >>"$LOG" 2>&1 </dev/null &
fi
# 不 wait 后台进程；立即返回，绝不阻塞 Stop。
exit 0
