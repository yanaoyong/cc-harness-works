#!/usr/bin/env bash
# harness_bootstrap.sh — plugin 分发后一键就绪（A/B 共享单一实现 · AC-5 禁止双实现）
# 变更卡：feat-plugin-bootstrap-automation-20260705（spec §2 A-1/A-3/S-1/S-2/B-4）
#
# 六步序列（S-1 · 全步骤幂等可重入）：
#   ① 组件持久落盘 $TOP/.harness/components/{codegraph,wiki-engine}
#      （源=本仓 plugins/ → plugin 缓存 $CLAUDE_PLUGIN_ROOT；已存在且同内容跳过 · F-2）
#   ② 探测/安装 codegraph 引擎（下载 install.sh 后比对 sha256 才执行 · fail-closed · AC-8/OQ-1(b)）
#   ③ 安装后按上游 install.sh 已知落盘位置**绝对路径**探测 codegraph 二进制，
#      注入本进程 PATH（不依赖 shell rc 刷新 · F-5）
#   ④ cg init 建索引（.codegraph/ 已存在则跳过）
#   ⑤ wiki 骨架（mkdir + 占位 README + wiki-rescan --init · 幂等判据 = wiki/_meta/state.json
#      存在即跳过骨架落盘 · F-7）+ skill 注册（wiki-engine install.sh + cg install-skill ·
#      注入一律经 .harness/components/ 持久副本 · 禁止指向版本化 plugin 缓存 · F-2/F-4）
#   ⑥ 就绪报告（stdout）+ 哨兵
#
# 旗标：
#   --yes          非交互（B 路径首会话默认授权〔opt-out 逃生阀关闭前 · ADR-015〕；A 路径 command 向用户确认后传入）
#   --report-only  只探测三项就绪态（engine/index/wiki）并输出，零写入；
#                  输出固定三行 key=value（engine=ready|missing / index=… / wiki=…），
#                  全就绪 exit 0、有缺项 exit 20（供 T4 hint hook 机读；优先级高于其他旗标）
#   --background   自后台化（nohup 重跑自身 --yes），本进程秒退 exit 0（F-3 · B 路径支撑）；
#                  日志：$STATE_DIR/bootstrap.log（每次后台运行覆写 = 最近一次结果语义；
#                  STATE_DIR=${HARNESS_STATE_DIR:-$TOP/.harness/state} · 项目本地 · ADR-016）
#
# 退出码（可控枚举 · 恒不崩溃态；hook 调用侧〔T3/T4〕负责吞非零码保证恒 exit 0）：
#   0   全就绪（engine+index+wiki state 齐 · 无降级项）
#   20  部分完成（降级：有步骤跳过/失败，但已尽力推进；report-only 有缺项也用 20）
#   21  校验失败/校验值缺失拒装（fail-closed · AC-8）
#   22  无网络 / 无 curl / 下载失败或超时
#   2   用法错误 / 无法定位仓库根
#
# 哨兵（独立于 .scaffold_initialized · B-3）：均落 $STATE_DIR（${HARNESS_STATE_DIR:-$TOP/.harness/state} · 项目本地 · ADR-016）
#   .bootstrap_running  后台执行中（--background 父进程落盘，内容=子进程 pid；run 结束移除）
#   .bootstrap_done     最近一次执行全就绪（仅 exit 0 时落；失败则移除 → 下会话重试判据）
#   .bootstrap_failed   最近一次执行失败（内容 exit_code=/reason=/time= · 供 T4 接力诊断）
#
# 环境变量（key/token 零硬编码：本脚本不读写任何 API key）：
#   HARNESS_BOOTSTRAP_SHA256          覆盖内置 install.sh sha256 pin（优先于内置值生效）
#   HARNESS_CODEGRAPH_INSTALL_URL     覆盖 install.sh 下载 URL（T6 离线 fixture/stub 用）
#   HARNESS_BOOTSTRAP_BIN_CANDIDATES  追加引擎二进制探测候选路径（空白分隔 · 测试 stub 用）
#   HARNESS_BOOTSTRAP_BG              内部旗标：=1 表示当前进程是后台子进程（勿手工设置）
#   CODEGRAPH_DIST / CODEGRAPH_NODE   尊重既有 dev 运行时（视作引擎已就绪，跳过安装）
#
# bash 3.2 兼容：不使用 declare -A / 关联数组 / mapfile / readarray
set -uo pipefail

PREFIX="[harness:bootstrap]"

log_info() { echo "$PREFIX $*" >&2; }
log_warn() { echo "$PREFIX ⚠️  $*" >&2; }

usage() {
  cat >&2 <<'USAGE'
用法：harness_bootstrap.sh [--yes] [--report-only] [--background]
  --yes          非交互模式（跳过引擎安装确认；B 路径首会话默认授权〔opt-out · ADR-015〕/ A 路径用户确认后传入）
  --report-only  只探测 engine/index/wiki 三项就绪态并输出，零写入（全就绪 0 / 有缺项 20）
  --background   nohup 自后台化，本进程秒退（日志 $STATE_DIR/bootstrap.log）
退出码：0 全就绪 / 20 部分完成(降级) / 21 校验失败或缺失拒装 / 22 无网络或下载失败 / 2 用法或环境错误
USAGE
}

# ============================================================
# 旗标解析
# ============================================================

YES=0
REPORT_ONLY=0
BACKGROUND=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes)         YES=1 ;;
    --report-only) REPORT_ONLY=1 ;;
    --background)  BACKGROUND=1 ;;
    -h|--help)     usage; exit 0 ;;
    *)             log_warn "未知旗标：$1"; usage; exit 2 ;;
  esac
  shift
done

# ============================================================
# 守卫：仓库根定位（对齐 session-start.sh 先例）
# ============================================================

TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$TOP" ]; then
  log_warn "无法定位仓库根（非 git 仓库），bootstrap 需在项目仓库内运行"
  exit 2
fi
cd "$TOP" || exit 2

STATE_DIR="${HARNESS_STATE_DIR:-$TOP/.harness/state}"
LOG_FILE="$STATE_DIR/bootstrap.log"

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$SELF_DIR/$(basename "$0")"

# ============================================================
# 引擎安装源与 sha256 pin（OQ-1 决议 (b)：下载后比对内置 sha256 再执行）
# ============================================================

CODEGRAPH_INSTALL_URL="${HARNESS_CODEGRAPH_INSTALL_URL:-https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh}"

# ── pin 刷新纪律（随 plugin 发版刷新 · HITL-1 OQ-1 决议）──
#   每次 plugin 发版前，维护者执行：
#     curl -fsSL "$CODEGRAPH_INSTALL_URL" | sha256sum
#   把 64 位十六进制结果替换下行占位值（并一并核对下方 _known_candidates 落盘位置清单
#   是否仍与上游 install.sh 行为一致）。运行时可用 HARNESS_BOOTSTRAP_SHA256 覆盖（优先）。
#   占位值/非法值（非 64hex）→ fail-closed 拒装（AC-8），绝不放行未校验的远程脚本。
BUILTIN_INSTALL_SHA256="f4e90c6e0c1d2ac95a43fa6e82e4caf76fabdb18310afc72597314b58632e56c"  # v0.7.0 发版复核 · 2026-07-05 与上游实测一致（curl+sha256sum 复跑）

# ============================================================
# 工具函数
# ============================================================

_sha256_file() {
  # $1 = 文件路径；输出 sha256（无 sha256 工具输出空 → 调用方 fail-closed）
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  else
    echo ""
  fi
}

_engine_on_path() {
  # 引擎可见判据（对齐 bin/cg 运行时探测语义）：codegraph 上 PATH，或 dev 运行时已配
  command -v codegraph >/dev/null 2>&1 && return 0
  [ -n "${CODEGRAPH_DIST:-}" ] && [ -f "${CODEGRAPH_DIST:-/nonexistent}" ] && return 0
  return 1
}

_known_candidates() {
  # 上游 colbymchenry/codegraph install.sh 已知/常见落盘位置（F-5 · 绝对路径探测清单）。
  # 该清单为 best-effort，随 sha256 pin 刷新时一并核对上游脚本实际落盘位置；
  # 测试/特殊环境可经 HARNESS_BOOTSTRAP_BIN_CANDIDATES 前置追加候选。
  if [ -n "${HARNESS_BOOTSTRAP_BIN_CANDIDATES:-}" ]; then
    # shellcheck disable=SC2086
    printf '%s\n' ${HARNESS_BOOTSTRAP_BIN_CANDIDATES}
  fi
  if [ -n "${HOME:-}" ]; then
    printf '%s\n' \
      "$HOME/.codegraph/bin/codegraph" \
      "$HOME/.local/bin/codegraph" \
      "$HOME/bin/codegraph"
  fi
  printf '%s\n' \
    "/usr/local/bin/codegraph" \
    "/opt/codegraph/bin/codegraph"
}

_probe_engine_binary() {
  # 按已知位置绝对路径探测可执行二进制；命中输出路径 return 0，全 miss return 1
  local c
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ -x "$c" ]; then
      printf '%s\n' "$c"
      return 0
    fi
  done < <(_known_candidates)
  return 1
}

_ensure_engine_visible() {
  # F-5：不依赖 shell rc/PATH 刷新——探测到已知位置二进制即注入本进程 PATH
  _engine_on_path && return 0
  local found
  found="$(_probe_engine_binary)" || return 1
  PATH="$(dirname "$found"):$PATH"
  export PATH
  log_info "已按绝对路径探测到引擎二进制并注入本进程 PATH：$found（F-5）"
  return 0
}

_locate_cg() {
  # bin/cg 三级回退链（A-3 · 对齐 session_start_wiki_freshness.sh 先例；
  # 第③级先判 CLAUDE_PLUGIN_ROOT 非空 · 承 failure-record-001）
  if [ -r "$TOP/.harness/components/codegraph/bin/cg" ]; then
    printf '%s\n' "$TOP/.harness/components/codegraph/bin/cg"
  elif [ -r "$TOP/plugins/harness-core/components/codegraph/bin/cg" ]; then
    printf '%s\n' "$TOP/plugins/harness-core/components/codegraph/bin/cg"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/components/codegraph/bin/cg" ]; then
    printf '%s\n' "${CLAUDE_PLUGIN_ROOT}/components/codegraph/bin/cg"
  else
    return 1
  fi
}

_locate_rescan() {
  # wiki-rescan 三级回退链（A-3 · 只读/骨架用途，三级均可；注册类注入见步骤⑤仅限链①）
  if [ -r "$TOP/.harness/components/wiki-engine/bin/wiki-rescan" ]; then
    printf '%s\n' "$TOP/.harness/components/wiki-engine/bin/wiki-rescan"
  elif [ -r "$TOP/plugins/harness-core/components/wiki-engine/bin/wiki-rescan" ]; then
    printf '%s\n' "$TOP/plugins/harness-core/components/wiki-engine/bin/wiki-rescan"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/components/wiki-engine/bin/wiki-rescan" ]; then
    printf '%s\n' "${CLAUDE_PLUGIN_ROOT}/components/wiki-engine/bin/wiki-rescan"
  else
    return 1
  fi
}

# ============================================================
# --report-only：三项就绪态探测（A-2 检测项对齐 · 零写入 · 最先处理）
# ============================================================

if [ "$REPORT_ONLY" -eq 1 ]; then
  eng="missing"; idx="missing"; wik="missing"; miss=0
  if _engine_on_path || _probe_engine_binary >/dev/null 2>&1; then eng="ready"; else miss=1; fi
  if [ -d "$TOP/.codegraph" ]; then idx="ready"; else miss=1; fi
  if [ -d "$TOP/wiki" ]; then wik="ready"; else miss=1; fi
  echo "engine=$eng"
  echo "index=$idx"
  echo "wiki=$wik"
  if [ "$miss" -eq 0 ]; then exit 0; else exit 20; fi
fi

# ============================================================
# --background：自后台化（F-3 · 父进程秒退，不占 SessionStart 60s 预算）
# ============================================================

if [ "$BACKGROUND" -eq 1 ] && [ "${HARNESS_BOOTSTRAP_BG:-0}" != "1" ]; then
  mkdir -p "$STATE_DIR" 2>/dev/null
  # 自忽略：STATE_DIR 现项目本地（ADR-016），幂等写 `*` 防运行时哨兵/日志被 commit
  [ -f "$STATE_DIR/.gitignore" ] || printf '*\n' > "$STATE_DIR/.gitignore" 2>/dev/null
  {
    echo "== harness bootstrap 后台运行 · $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
  } > "$LOG_FILE" 2>/dev/null
  # R4-04：不在此处预清 .bootstrap_failed——新结果未知前抹掉会丢上次失败诊断
  # （若本次后台被强杀，failed 与 running 双失、无迹可循）。failed 哨兵的
  # 落盘/清除生命周期完全归子进程 finish() 处置（成功 rm / 失败覆写）。
  HARNESS_BOOTSTRAP_BG=1 nohup "$SELF" --yes >>"$LOG_FILE" 2>&1 </dev/null &
  bg_pid=$!
  # R4-04 顺序评估留痕：running 哨兵须写子 pid，故只能 nohup 取得 $! 后落盘；
  # 「子进程先到 finish() 清哨兵、父进程再写回」的窗口理论存在（子进程要跑完
  # 全六步，实际窗口极小），且残留形态已被 R4-01 自愈覆盖——session-start
  # `_maybe_auto_bootstrap` 与 hint hook 分支 A 均按 kill -0 判 pid 存活，
  # 死 pid 残留哨兵不再短路重试/接力路径（session-start 侧还会清除残留）。
  # 故不引入两段式占位写入等额外复杂度，仅以本注释固化论证。
  echo "$bg_pid" > "$STATE_DIR/.bootstrap_running" 2>/dev/null
  log_info "bootstrap 已后台化（pid $bg_pid）· 日志：$LOG_FILE · 结果哨兵：.bootstrap_done/.bootstrap_failed"
  exit 0
fi

# ============================================================
# 收尾：哨兵落盘 + 可控退出（B-3 · 独立于 .scaffold_initialized）
# ============================================================

finish() {
  local code="$1" reason
  mkdir -p "$STATE_DIR" 2>/dev/null
  [ -f "$STATE_DIR/.gitignore" ] || printf '*\n' > "$STATE_DIR/.gitignore" 2>/dev/null  # 自忽略（ADR-016）
  rm -f "$STATE_DIR/.bootstrap_running" 2>/dev/null
  if [ "$code" -eq 0 ]; then
    touch "$STATE_DIR/.bootstrap_done" 2>/dev/null
    rm -f "$STATE_DIR/.bootstrap_failed" 2>/dev/null
    log_info "bootstrap 全就绪 ✅（哨兵已落：$STATE_DIR/.bootstrap_done）"
  else
    case "$code" in
      21) reason="checksum-refused" ;;
      22) reason="network" ;;
      *)  reason="partial" ;;
    esac
    rm -f "$STATE_DIR/.bootstrap_done" 2>/dev/null
    {
      echo "exit_code=$code"
      echo "reason=$reason"
      echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$STATE_DIR/.bootstrap_failed" 2>/dev/null
    log_warn "bootstrap 未全就绪（exit=$code reason=$reason）· .bootstrap_done 不落 → 下会话重试 / 跑 /harness-core:bootstrap 手动兜底"
  fi
  exit "$code"
}

# 失败聚合旗标（退出码优先级：21 > 22 > 20）
DEGRADED=0
CHECKSUM_REFUSED=0
NETWORK_FAILED=0

# ============================================================
# 步骤①：组件持久落盘 .harness/components/（F-2 · 链①在消费方成真）
# ============================================================

_persist_component() {
  # $1 = 组件名；0 = 持久落点可用，1 = 不可用（降级）
  local name="$1" src="" dst copied=0 failed=0 f rel
  dst="$TOP/.harness/components/$name"
  if [ -d "$TOP/plugins/harness-core/components/$name" ]; then
    src="$TOP/plugins/harness-core/components/$name"          # 本仓开发态
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/components/$name" ]; then
    src="${CLAUDE_PLUGIN_ROOT}/components/$name"              # plugin 缓存（消费方安装态）
  fi
  if [ -z "$src" ]; then
    if [ -d "$dst" ]; then
      log_info "组件 $name：源不可见但持久落点已存在（$dst），视为已落盘"
      return 0
    fi
    log_warn "组件 $name：plugin 缓存/本仓 plugins/ 均无源且持久落点缺失，跳过（降级）"
    return 1
  fi
  if [ "$src" = "$dst" ]; then
    return 0
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#$src/}"
    if [ -f "$dst/$rel" ] && cmp -s "$f" "$dst/$rel" 2>/dev/null; then
      continue    # 已存在且同内容 → 跳过（幂等）
    fi
    mkdir -p "$(dirname "$dst/$rel")" 2>/dev/null
    if cp -p "$f" "$dst/$rel" 2>/dev/null; then
      copied=$((copied + 1))
    else
      failed=$((failed + 1))
    fi
  done < <(find "$src" -type f 2>/dev/null)
  if [ "$failed" -gt 0 ]; then
    log_warn "组件 $name：$failed 个文件落盘失败（已落 $copied 个）"
    return 1
  fi
  if [ "$copied" -gt 0 ]; then
    log_info "✅ 组件 $name 已持久落盘 → $dst（$copied 个文件）"
  else
    log_info "组件 $name 持久落点已同步（零写入 · 幂等）"
  fi
  return 0
}

CODEGRAPH_HOME_OK=0
WIKI_HOME_OK=0
if _persist_component codegraph;   then CODEGRAPH_HOME_OK=1; else DEGRADED=1; fi
if _persist_component wiki-engine; then WIKI_HOME_OK=1;      else DEGRADED=1; fi

# ============================================================
# 步骤②：探测/安装引擎（sha256 fail-closed · AC-8）
# ============================================================

_install_engine() {
  local eff eff_src tmp maxtime actual actual_lc eff_lc
  eff="${HARNESS_BOOTSTRAP_SHA256:-$BUILTIN_INSTALL_SHA256}"
  eff_src="内置 pin"
  [ -n "${HARNESS_BOOTSTRAP_SHA256:-}" ] && eff_src="HARNESS_BOOTSTRAP_SHA256 环境变量"

  # fail-closed：校验值缺省/占位/非法 → 拒绝安装（AC-8），绝不放行未校验远程脚本
  if ! printf '%s' "$eff" | grep -Eiq '^[0-9a-f]{64}$'; then
    CHECKSUM_REFUSED=1
    log_warn "install.sh sha256 pin 缺省或非法（当前值「$eff」· 来源：$eff_src）——fail-closed 拒装（AC-8）。"
    log_warn "  兜底：设 HARNESS_BOOTSTRAP_SHA256=<64位hex> 后重跑，或按 components/codegraph/USAGE.md §1 手动安装引擎"
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    NETWORK_FAILED=1
    log_warn "curl 不可用，无法下载引擎 install.sh（跳过安装 · 手动兜底见 components/codegraph/USAGE.md §1）"
    return 1
  fi

  # 安装前展示将执行的动作（A-1 ②：下载 URL / 校验值 / 落盘位置）
  log_info "将执行的引擎安装动作："
  log_info "  下载 URL  : $CODEGRAPH_INSTALL_URL"
  log_info "  sha256 pin: $eff（来源：$eff_src · 校验通过才执行）"
  log_info "  预期落盘  : 上游 install.sh 既定位置（\$HOME/.codegraph 等，见脚本内候选清单）"
  if [ "$YES" -ne 1 ]; then
    if [ -t 0 ]; then
      printf '%s 确认执行上述安装动作？[y/N] ' "$PREFIX" >&2
      local ans=""
      read -r ans || ans=""
      case "$ans" in
        y|Y|yes|YES) : ;;
        *) log_warn "用户未确认，跳过引擎安装（非交互场景请传 --yes）"; DEGRADED=1; return 1 ;;
      esac
    else
      log_warn "非交互环境且未传 --yes，显式授权缺失，跳过引擎安装"
      DEGRADED=1
      return 1
    fi
  fi

  tmp="$(mktemp "${TMPDIR:-/tmp}/harness_bootstrap_install.XXXXXX" 2>/dev/null)" || {
    log_warn "mktemp 失败，跳过引擎安装"
    DEGRADED=1
    return 1
  }
  # F-3：--max-time 120 仅 A 同步路径；B 后台子进程不设总时长上限（仅保留连接超时护栏）
  maxtime="--max-time 120"
  [ "${HARNESS_BOOTSTRAP_BG:-0}" = "1" ] && maxtime=""
  # shellcheck disable=SC2086
  if ! curl -fsSL --connect-timeout 20 $maxtime "$CODEGRAPH_INSTALL_URL" -o "$tmp" 2>/dev/null; then
    NETWORK_FAILED=1
    rm -f "$tmp" 2>/dev/null
    log_warn "install.sh 下载失败（无网络/超时/不可达），跳过安装；下会话重试或跑 /harness-core:bootstrap 手动兜底"
    return 1
  fi

  actual="$(_sha256_file "$tmp")"
  if [ -z "$actual" ]; then
    CHECKSUM_REFUSED=1
    rm -f "$tmp" 2>/dev/null
    log_warn "环境无 sha256 工具（sha256sum/shasum），无法校验 install.sh——fail-closed 拒装（AC-8）"
    return 1
  fi
  actual_lc="$(printf '%s' "$actual" | tr 'A-Z' 'a-z')"
  eff_lc="$(printf '%s' "$eff" | tr 'A-Z' 'a-z')"
  if [ "$actual_lc" != "$eff_lc" ]; then
    CHECKSUM_REFUSED=1
    rm -f "$tmp" 2>/dev/null
    log_warn "install.sh sha256 校验失败（实测 $actual_lc ≠ pin $eff_lc）——拒绝执行（AC-8 · 上游可能已更新，等 plugin 发版刷新 pin 或核实后用 HARNESS_BOOTSTRAP_SHA256 覆盖）"
    return 1
  fi

  log_info "sha256 校验通过，执行 install.sh ..."
  if sh "$tmp" >&2; then
    rm -f "$tmp" 2>/dev/null
    log_info "✅ install.sh 执行完成"
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  DEGRADED=1
  log_warn "install.sh 执行失败（rc≠0），走安装失败路径（AC-4）"
  return 1
}

ENGINE_READY=0
if _ensure_engine_visible; then
  ENGINE_READY=1
  log_info "引擎已就绪，跳过安装（幂等）"
else
  if _install_engine; then
    # 步骤③：安装后同进程二进制定位（F-5 · 不依赖 shell rc）
    if _ensure_engine_visible; then
      ENGINE_READY=1
    else
      DEGRADED=1
      log_warn "install.sh 执行后仍未在已知位置探测到 codegraph 二进制 = 安装失败路径（F-5/AC-4）；报告以 cg doctor 实测为准"
    fi
  fi
fi

# ============================================================
# 步骤④：cg init 建索引（.codegraph/ 已存在则跳过 · S-2）
# ============================================================

CG="$(_locate_cg || true)"
if [ -d "$TOP/.codegraph" ]; then
  log_info "索引已存在（$TOP/.codegraph/），跳过 cg init（幂等）"
elif [ "$ENGINE_READY" -eq 1 ] && [ -n "$CG" ]; then
  log_info "开始 cg init 建索引（大仓可能耗时较长，就绪可能跨会话分步达成）..."
  if CG_PROJECT="$TOP" sh "$CG" init >&2; then
    log_info "✅ cg init 完成"
  else
    DEGRADED=1
    log_warn "cg init 失败（rc=$?），跳过（下次重跑 bootstrap 或手动 cg init）"
  fi
else
  DEGRADED=1
  if [ -z "$CG" ]; then
    log_warn "bin/cg 三级回退链全不命中，跳过 cg init（降级）"
  else
    log_warn "引擎未就绪，跳过 cg init（降级 · 引擎就绪后由 hint hook 接力或重跑 bootstrap）"
  fi
fi

# ============================================================
# 步骤⑤：wiki 骨架 + skill 注册（OQ-2(b) 全量骨架 · F-7 幂等判据）
# ============================================================

# 5a. wiki 骨架落盘（幂等判据 = wiki/_meta/state.json 存在即跳过骨架子步 · F-7：
#     wiki-rescan --init 在 state 已存在时硬退 exit 2「不重复 init」，必须预检）
if [ -f "$TOP/wiki/_meta/state.json" ]; then
  log_info "wiki 骨架已存在（wiki/_meta/state.json），跳过骨架落盘（幂等 · F-7）"
else
  mkdir -p "$TOP/wiki" 2>/dev/null
  if [ ! -f "$TOP/wiki/README.md" ]; then
    cat > "$TOP/wiki/README.md" <<'EOF'
# Wiki（骨架占位）

> 本目录由 harness bootstrap 落盘（只落骨架、不摄取）。
> 注入 `DEEPSEEK_API_KEY`（环境变量，勿写入任何文件）后，按 wiki-engine SKILL.md
> 五条工作流增量摄取（WK-S 随卡增量纪律）。
EOF
    log_info "✅ wiki/README.md 占位已落盘"
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    DEGRADED=1
    log_warn "python3 不可用，跳过 wiki-rescan --init（wiki state 基线未落）"
  else
    RESCAN="$(_locate_rescan || true)"
    if [ -z "$RESCAN" ]; then
      DEGRADED=1
      log_warn "wiki-rescan 三级回退链全不命中，跳过 wiki state 初始化（降级）"
    else
      init_out="$(python3 "$RESCAN" --wiki wiki --init --source-dir .harness/changes/ 2>&1)"
      init_rc=$?
      if [ "$init_rc" -eq 0 ]; then
        log_info "✅ wiki state 基线已落（wiki/_meta/state.json · 源=.harness/changes/）"
      else
        DEGRADED=1
        log_warn "wiki-rescan --init 失败（rc=$init_rc）：$init_out"
      fi
    fi
  fi
fi

# 5a-bis. wiki-background 集合根骨架落盘（与 5a wiki/ 对称 · best-effort 非门禁）
#   幂等判据 = wiki-background/README.md 存在即跳过（与 5a wiki state 解耦，独立顶层块，
#   不嵌 5a 的 else 分支 · INFO-2）。旁路定性（ADR-005 + WK-B2 缺位降级）：任何路径都
#   不置 DEGRADED、不入 FINAL_READY、不阻断 bootstrap（AC-3）。只 ever 创建 README.md，
#   从不触碰 wiki-background/ 下其它文件（保护用户既有语料 · AC-2/INFO-1）。
#   不 wiki-rescan --init：wiki-background/ 是 corpus 集合根、非单个 wiki（wiki 是其
#   <corpus>/ 子目录，各自持 _meta/state.json），根级无 state.json 语义。
mkdir -p "$TOP/wiki-background" 2>/dev/null
if [ ! -f "$TOP/wiki-background/README.md" ]; then
  cat > "$TOP/wiki-background/README.md" <<'EOF'
# 背景知识 wiki 集合根 · wiki-background/

> 本目录由 harness bootstrap 落盘（只落骨架、0 实际语料）。

## corpus 布局

`wiki-background/<corpus>/` 每个子目录 = 一个独立背景 corpus，结构同构于项目文档
wiki `wiki/`（`index.md` + 互链 markdown 页面 + `_meta/`）。组件按
`--wiki wiki-background/<corpus>/` 单 corpus 语义消费（路径为仓库根相对路径）。

## 消费纪律

corpus-aware 路由 / 缺位优雅降级 / 批判性平衡吸收，权威源见
`文档wiki查询与摄取规范.md` §5 WK-B（本占位单向引用，不复制正文）。

## 集成深度

旁路查询工具产物根（ADR-005）——不进任一阶段门禁、缺位不阻塞主流程。
EOF
  log_info "✅ wiki-background/README.md 占位已落盘（背景 corpus 集合根 · 旁路）"
fi

# 5b. skill 注册（本身幂等：ln -sfn / SKILL.md 覆写 → 骨架已存在也照常刷新注册，
#     修复「wiki 已在而 skill 未注册」缝隙；F-7 的整步跳过语义仅约束 5a 防 rescan exit 2）。
#     F-2 硬约束：注册注入的路径一律经 .harness/components/ 持久副本产生——
#     wiki-engine install.sh 的 symlink 指回其自身所在目录、cg install-skill 注入被调用 cg
#     的绝对路径，故【只允许调用链①持久副本】，链①缺失即跳过，绝不回退 plugin 缓存注册。
if [ "$WIKI_HOME_OK" -eq 1 ] && [ -f "$TOP/.harness/components/wiki-engine/install.sh" ]; then
  if bash "$TOP/.harness/components/wiki-engine/install.sh" --repo-root "$TOP" >&2; then
    log_info "✅ wiki-engine skill 已注册（链接指向 .harness/components/wiki-engine/）"
  else
    DEGRADED=1
    log_warn "wiki-engine install.sh 注册失败（rc≠0）"
  fi
else
  DEGRADED=1
  log_warn "wiki-engine 持久副本缺失，跳过 skill 注册（F-2：禁止从 plugin 缓存注册）"
fi

if [ "$CODEGRAPH_HOME_OK" -eq 1 ] && [ -r "$TOP/.harness/components/codegraph/bin/cg" ]; then
  if sh "$TOP/.harness/components/codegraph/bin/cg" install-skill "$TOP" >&2; then
    log_info "✅ codegraph skill 已注册（注入 cg 路径 = .harness/components/codegraph/bin/cg）"
  else
    DEGRADED=1
    log_warn "cg install-skill 注册失败（rc≠0）"
  fi
else
  DEGRADED=1
  log_warn "codegraph 持久副本缺失，跳过 cg install-skill（F-2：禁止从 plugin 缓存注册）"
fi

# ============================================================
# 步骤⑥：就绪报告（stdout · 以实测为准）+ 哨兵
# ============================================================

eng_line="⚠️ 缺失（runtime NONE · 手动兜底见 components/codegraph/USAGE.md §1）"
_engine_on_path && eng_line="✅ 就绪"
idx_line="⚠️ 缺失（.codegraph/ 不存在 · 引擎就绪后跑 cg init）"
[ -d "$TOP/.codegraph" ] && idx_line="✅ 就绪（$TOP/.codegraph）"
wiki_line="⚠️ 缺失（wiki/_meta/state.json 未落）"
[ -f "$TOP/wiki/_meta/state.json" ] && wiki_line="✅ 骨架就绪（wiki/_meta/state.json）"
cg_skill_line="⚠️ 未注册"
[ -f "$TOP/.claude/skills/codegraph/SKILL.md" ] && cg_skill_line="✅ 已注册"
wiki_skill_line="⚠️ 未注册"
[ -e "$TOP/.claude/skills/wiki-engine" ] && wiki_skill_line="✅ 已注册"

echo "== harness bootstrap 就绪报告 =="
echo "engine : $eng_line"
echo "index  : $idx_line"
echo "wiki   : $wiki_line"
echo "skills : codegraph=$cg_skill_line · wiki-engine=$wiki_skill_line"
if [ -n "$CG" ]; then
  echo "--- cg doctor（实测）---"
  CG_PROJECT="$TOP" sh "$CG" doctor 2>&1 || true
fi
echo "--- 后续步骤 ---"
echo "· wiki 摄取：export DEEPSEEK_API_KEY=...（勿写入文件）后按 wiki-engine SKILL.md 批循环摄取（bootstrap 只落骨架）"
echo "· 有缺项可重跑 /harness-core:bootstrap（全步骤幂等）"

# 全就绪判定（严于 report-only 的三项目录级检测：wiki 以 state.json 为准 · AC-1c/OQ-2(b)）
FINAL_READY=1
_engine_on_path || FINAL_READY=0
[ -d "$TOP/.codegraph" ] || FINAL_READY=0
[ -f "$TOP/wiki/_meta/state.json" ] || FINAL_READY=0

if [ "$CHECKSUM_REFUSED" -eq 1 ]; then
  finish 21
elif [ "$NETWORK_FAILED" -eq 1 ]; then
  finish 22
elif [ "$FINAL_READY" -eq 1 ] && [ "$DEGRADED" -eq 0 ]; then
  finish 0
else
  finish 20
fi
