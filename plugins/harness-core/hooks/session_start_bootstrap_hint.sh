#!/usr/bin/env bash
# SessionStart 钩子（detect-only + B 路径接力）：bootstrap 就绪提示（方案 A 的发现面）
# 变更卡 feat-plugin-bootstrap-automation-20260705 · T4。落地 spec §2 A-2（含 F-8 闭合）+
# B-4/F-3 接力职责：每会话零成本检测三项就绪状态——
#   ① 引擎 runtime（cg doctor 探测 · 前置已知落盘位置 PATH 注入，对齐 F-5 同款候选清单）
#   ② 索引（$TOP/.codegraph/ 目录存在）
#   ③ wiki（$TOP/wiki/ 目录存在 · 目录级判据，刻意与 harness_bootstrap.sh --report-only 对齐）
# 三缺任一 → stderr 恰一行「跑 /harness-core:bootstrap 一键就绪（缺:<缺项列表>）」；
# 三全 → 零输出；任何路径恒 exit 0（AC-2 · 非阻断 · 不进门禁 · ADR-005 旁路语义）。
#
# == detect-only 红线与唯一例外写入分支（F-3 接力）==
# 本 hook 默认 detect-only：零写入、零出站（cg doctor / 目录检测均为本地只读）。
# **唯一例外** = B 路径接力分支：后台 bootstrap（T3 nohup）已把引擎装好而索引未建、且
# opt-in 开关开（HARNESS_AUTO_BOOTSTRAP=1 ∨ config `bootstrap.auto: true` grep 单行解析
# · OQ-4 决议）→ 本 hook 接力 `cg init`（可写入 .codegraph/ 索引；失败吞掉 warning 一行）。
# 其余任何路径不写任何文件（含不清理残留哨兵）。
#
# 后台哨兵消费（T1 契约 · t1_notes §1.3，均在 $STATE_DIR）：
#   .bootstrap_running：后台进行中（内容=子 pid）→ 提示一行、不接力（pid 已死的残留哨兵
#                       视作未在运行，落入后续分支；detect-only 不代为清理）。
#   .bootstrap_failed ：最近一次失败（三行 exit_code=/reason=/time=）→ 读 reason 提示一行。
#   bootstrap.log     ：仅在提示行里给路径供用户跟进，本 hook 不读不写其内容。
# STATE_DIR 取法与 session-start.sh / harness_bootstrap.sh 完全一致。
#
# 守卫短路（对齐 session_start_wiki_freshness.sh detect-only 先例）：
#   ①仓库根定位 → ②bin/cg 三级回退链定位（.harness/ 消费方安装态 → plugins/harness-core/
#   本仓开发态 → $CLAUDE_PLUGIN_ROOT/ plugin 包内直读 · 首个可读即用；第③级先判
#   CLAUDE_PLUGIN_ROOT 非空，承 failure-record-001）→ **全不命中 → 静默 exit 0（F-8 闭合，
#   不视作"检测项①缺"、不打提示行）** → 三项检测 → 分支输出。
# 所有提示走 stderr，统一前缀 [harness:bootstrap_hint]；任何路径最终 exit 0。
#
# bash 3.2 兼容（NFR）：无 declare -A / mapfile / readarray / bash4-only 语法。
set -uo pipefail

PREFIX="[harness:bootstrap_hint]"

# 守卫①：自定位仓库根；非 git / 定位失败 → 静默退出 0
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TOP" ] && exit 0
cd "$TOP" || exit 0

# 守卫②：bin/cg 三级回退链定位（全不命中 → 静默 exit 0 · F-8）
CG=""
if [ -r "$TOP/.harness/components/codegraph/bin/cg" ]; then
  # 链①：消费方安装态（bootstrap 第①步持久落盘后成真）
  CG="$TOP/.harness/components/codegraph/bin/cg"
elif [ -r "$TOP/plugins/harness-core/components/codegraph/bin/cg" ]; then
  # 链②：本仓开发态
  CG="$TOP/plugins/harness-core/components/codegraph/bin/cg"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/components/codegraph/bin/cg" ]; then
  # 链③：plugin 包内直读（先判 CLAUDE_PLUGIN_ROOT 非空）
  CG="${CLAUDE_PLUGIN_ROOT}/components/codegraph/bin/cg"
fi
[ -z "$CG" ] && exit 0

STATE_DIR="${CLAUDE_PLUGIN_DATA:-$TOP/.harness/state}"

# 已知落盘位置 PATH 注入（F-5 同款候选清单 · 仅注入本进程 · 纯探测零写入）：
# 上游 install.sh 把 PATH 写 shell rc，hook 进程不生效——后台 bootstrap 装好的引擎若不在
# 本进程 PATH，doctor 会误报 NONE、接力分支永不触发。故 doctor 前先按已知位置探测。
# 两级探测（与 harness_bootstrap.sh / t1_notes §1.4 同一取值语义 · 双消费方契约一致）：
#   ① HARNESS_BOOTSTRAP_BIN_CANDIDATES = 空白分隔的引擎【二进制全路径】列表（T1 公示契约），
#      探测 [ -x "$cand" ] 命中 → 将其所在目录注入本进程 PATH；
#   ② 内置已知落盘【目录】清单（F-5 同款 5 处），探测 <目录>/codegraph 可执行。
if ! command -v codegraph >/dev/null 2>&1; then
  _found_dir=""
  # ① env 逃生口：条目 = 二进制全路径（勿传目录——与 harness_bootstrap.sh 消费语义一致）
  for _cand in ${HARNESS_BOOTSTRAP_BIN_CANDIDATES:-}; do
    if [ -n "$_cand" ] && [ -x "$_cand" ]; then
      _found_dir="$(dirname "$_cand")"
      break
    fi
  done
  # ② 内置已知落盘目录（F-5 同款候选清单）
  if [ -z "$_found_dir" ]; then
    for _d in "${HOME:-}/.codegraph/bin" "${HOME:-}/.local/bin" "${HOME:-}/bin" /usr/local/bin /opt/codegraph/bin; do
      if [ -n "$_d" ] && [ -x "$_d/codegraph" ]; then
        _found_dir="$_d"
        break
      fi
    done
  fi
  if [ -n "$_found_dir" ]; then
    PATH="$_found_dir:$PATH"
    export PATH
  fi
fi

# --- 三项检测（read-only）----------------------------------------------------
# ① 引擎 runtime：cg doctor（无 runtime 也恒可跑 · exit 0）。要求正向信号——doctor 输出
#   含 `runtime:` 行且非 `runtime: NONE` 才算就绪；doctor 整体失败/空输出按缺处理（保守）。
doctor_out="$(CG_PROJECT="$TOP" sh "$CG" doctor 2>/dev/null || true)"
engine_ok=0
if printf '%s\n' "$doctor_out" | grep -q '^runtime:' \
   && ! printf '%s\n' "$doctor_out" | grep -q '^runtime: NONE'; then
  engine_ok=1
fi
# ② 索引：.codegraph/ 目录（spec A-2 判据，与 cg is_initialized 同源）
index_ok=0
[ -d "$TOP/.codegraph" ] && index_ok=1
# ③ wiki：wiki/ 目录（目录级判据 · 刻意与 --report-only 三行对齐）
wiki_ok=0
[ -d "$TOP/wiki" ] && wiki_ok=1

# 三全 → 零输出（AC-2 硬项）
if [ "$engine_ok" = 1 ] && [ "$index_ok" = 1 ] && [ "$wiki_ok" = 1 ]; then
  exit 0
fi

# 缺项列表（bash 3.2 兼容 · 词与 --report-only 机读键一致：engine/index/wiki）
build_missing() {
  missing=""
  [ "$engine_ok" = 1 ] || missing="$missing engine"
  [ "$index_ok" = 1 ] || missing="$missing index"
  [ "$wiki_ok" = 1 ] || missing="$missing wiki"
  missing="${missing# }"
}
build_missing

# --- 分支输出（每路径恰一行 stderr + exit 0）---------------------------------

# 分支 A：后台 bootstrap 进行中（pid 存活）→ 提示、不接力
if [ -f "$STATE_DIR/.bootstrap_running" ]; then
  _pid="$(head -1 "$STATE_DIR/.bootstrap_running" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
    echo "$PREFIX 后台 bootstrap 进行中（pid=$_pid · 日志 $STATE_DIR/bootstrap.log · 缺:$missing）——本会话不接力" >&2
    exit 0
  fi
  # pid 已死的残留哨兵：视作未在运行，落入后续分支（detect-only 不代为清理哨兵）
fi

# opt-in 开关（与 T3 挂载同一语义：环境变量 ∨ config 单行键，取或 · OQ-4 决议）
# ⚠ 等价锚定：下方 grep 正则须与 session-start.sh `_auto_bootstrap_enabled`（约 L155）
#   的正则**完全一致**（容忍前导空白 / 键冒号前空白 / 行尾注释）。两文件无法共享函数，
#   以本注释互相指认——任一侧改动开关解析时必须同步另一侧，否则会出现
#   「T3 自动拉起、T4 拒绝接力」的开关半开态（t6_test_run_v1 缺陷 #2）。
switch_on=0
if [ "${HARNESS_AUTO_BOOTSTRAP:-0}" = "1" ]; then
  switch_on=1
elif [ -f "$TOP/HARNESS_CONFIG.yaml" ] \
     && grep -E -q '^[[:space:]]*bootstrap\.auto[[:space:]]*:[[:space:]]*true[[:space:]]*(#.*)?$' \
          "$TOP/HARNESS_CONFIG.yaml" 2>/dev/null; then
  switch_on=1
fi

# 分支 B：接力 cg init（唯一例外写入分支 · F-3 闭合）
# 触发条件 = 引擎已就绪（探测通过）且 .codegraph/ 缺失 且 开关开
if [ "$engine_ok" = 1 ] && [ "$index_ok" = 0 ] && [ "$switch_on" = 1 ]; then
  if CG_PROJECT="$TOP" sh "$CG" init >/dev/null 2>&1; then
    index_ok=1
    build_missing
    if [ -z "$missing" ]; then
      echo "$PREFIX 后台 bootstrap 接力：cg init 完成，三项已就绪" >&2
    else
      echo "$PREFIX 已接力 cg init——跑 /harness-core:bootstrap 一键就绪（缺:$missing）" >&2
    fi
  else
    # 失败吞掉：warning 一行 + 恒 exit 0（不阻断会话 · AC-4 语义）
    echo "$PREFIX 接力 cg init 失败——跑 /harness-core:bootstrap 一键就绪（缺:$missing）" >&2
  fi
  exit 0
fi

# 分支 C：上次后台 bootstrap 失败留痕 → 带 reason 提示一行
if [ -f "$STATE_DIR/.bootstrap_failed" ]; then
  fail_reason="$(sed -n 's/^reason=//p' "$STATE_DIR/.bootstrap_failed" 2>/dev/null | head -1)"
  echo "$PREFIX 上次后台 bootstrap 失败（reason=${fail_reason:-unknown}）——跑 /harness-core:bootstrap 一键就绪（缺:$missing）" >&2
  exit 0
fi

# 分支 D（默认）：detect-only 提示恰一行
echo "$PREFIX 跑 /harness-core:bootstrap 一键就绪（缺:$missing）" >&2

# 永不阻断会话（AC-2 · exit 0 硬准则）
exit 0
