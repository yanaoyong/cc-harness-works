#!/usr/bin/env bash
# session-start.sh — Harness Core Plugin SessionStart Hook
# 职责：当新项目安装 harness-core plugin 后，session 启动时自动初始化 .harness/ 结构；
#       存量项目则执行镜像单向自动同步（drift-sync：plugin 缓存 → 只读镜像 · ADR-013 裁决③⑤⑥）。
#
# 触发逻辑：
#   ① first-run 守卫：检查项目内 $TOP/.harness/state/.scaffold_initialized，已初始化则走 drift-sync 后退出
#   ② 若 .harness/changes/ 不存在 → 执行脚手架安装（新项目初始化）
#   ③ 若 .harness/changes/ 已存在 → 执行 drift-sync 单向自动同步（存量项目）
#   ④ 无 HARNESS_CONFIG.yaml 时仍触发 _scaffold_new_project（新用户场景）
#
# 组件加载边界（ADR-013 裁决①~④）：
#   - `.claude/commands/` 二次同步与 `.harness/hooks/` 副本已撤销（裁决①②）：commands 由官方 loader
#     以命名空间 /harness-core:* 原生加载；hooks 经 hooks.json 在 plugin 缓存内直接执行。
#     存量残留留置不删（处置权归用户），迁移提示见 plugins/README.md。
#   - `.harness/` 镜像（skills/agents/rules/commands + workflows 同步件）= 只读镜像 · 功能分发第二通道（裁决③）。
#   - workflows → .claude/workflows/ 为正当 workaround（官方 plugin 无 workflows 组件 · 裁决④）。
#
# 设计原则：
#   - 幂等：多次 session 启动不产生重复文件或报错；drift-sync 收敛后下次会话零写入
#   - 优雅降级：任何错误均不阻断 session 启动，仅打印 warning 到 stderr（fail-open 恒 exit 0）
#   - 不修改 git config，不产生全局副作用
#   - 永远 exit 0（不阻断 session）
#
# 哨兵 .scaffold_initialized 语义（fix-resident-contract-hook-consistency-20260702 显式化；
# 原「删除不复活」单语义已按 ADR-013 裁决⑤ 改写为对象级双语义）：
#   - 失败重试：脚手架安装有警告（had_error=1）时不落哨兵 → 将于下会话重试；每会话刷 warning 属预期行为，
#     直至一次全成功落哨兵为止
#   - 落点（项目本地 · fix-statedir-crossproject-leak-20260705 · ADR-016）：
#     STATE_DIR 恒项目本地 $TOP/.harness/state（仓库根绝对路径，不落 cwd）；
#     HARNESS_STATE_DIR 为可选覆盖逃生口。**不再取 CLAUDE_PLUGIN_DATA（宿主按插件全局，
#     会致跨项目哨兵泄漏——本卡 ADR-016 修复）**。
#   - 删除语义（对象级双语义 · ADR-013 裁决⑤）：
#     * 镜像件（.harness/skills|agents|rules|commands + workflows 同步件〔.harness/workflows 与
#       .claude/workflows〕）：删除=漂移的删除形态 → drift-sync 自动复活（权威源=plugin 缓存 · 单向）；
#       本地定制经基线三方比对告警跳过（裁决⑥ 方案 a），永不静默冲掉。
#     * 边界目录（_TEMPLATE / .harness/changes/** / .harness/state）：保留「删除不复活」（尊重用户删除）——
#       drift-sync 相位零写入（唯一例外：_TEMPLATE 整体缺失可补缺、存在永不覆盖；基线文件本身除外）；
#       重建走 /session-start --upgrade（裁决⑦ 手工逃生口）。
#
# bash 3.2 兼容：不使用 declare -A / 关联数组 / mapfile / readarray
set -uo pipefail

PREFIX="[harness:session-start]"

# ============================================================
# 工具函数
# ============================================================

log_info()  { echo "$PREFIX $*" >&2; }
log_warn()  { echo "$PREFIX ⚠️  $*" >&2; }
log_error() { echo "$PREFIX ❌ $*" >&2; }

# ------------------------------------------------------------
# checksum 工具探测（一次探测，全程复用）
# ------------------------------------------------------------

CHECKSUM_TOOL=""
CHECKSUM_TOOL_DETECTED=0

_detect_checksum_tool() {
  [ "$CHECKSUM_TOOL_DETECTED" -eq 1 ] && return 0
  CHECKSUM_TOOL_DETECTED=1
  if command -v sha256sum >/dev/null 2>&1; then
    CHECKSUM_TOOL="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    CHECKSUM_TOOL="shasum"
  elif command -v cksum >/dev/null 2>&1; then
    CHECKSUM_TOOL="cksum"
  fi
}

_file_checksum() {
  # $1 = 文件路径；输出内容 checksum（失败输出空 · fail-open）
  case "$CHECKSUM_TOOL" in
    sha256sum) sha256sum "$1" 2>/dev/null | awk '{print $1}' ;;
    shasum)    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' ;;
    cksum)     cksum "$1" 2>/dev/null | awk '{print $1 "-" $2}' ;;
    *)         echo "" ;;
  esac
}

# ------------------------------------------------------------
# 镜像件清单与基线（ADR-013 §3 硬条款表 · 裁决⑥ 方案 a）
# ------------------------------------------------------------

_mirror_pairs() {
  # 镜像件同步映射：<plugin 侧源>|<项目侧落点>|<基线 key 前缀>
  # 五类镜像（skills/agents/rules/commands/scripts → .harness/）+ workflows 同步件（双落盘）
  # scripts 镜像对（feat-plugin-display-parity）：statusline/list_flows + lib 三件 → .harness/scripts/；
  # 项目特定脚本（sync_public_marketplace.sh 等）不在 plugin 源内，drift-sync 天然不触碰
  printf '%s\n' \
    "$PLUGIN_SKILLS|$SKILLS_DIR|skills" \
    "$PLUGIN_AGENTS|$AGENTS_DIR|agents" \
    "$PLUGIN_RULES|$RULES_DIR|rules" \
    "$PLUGIN_ROOT/commands|$HARNESS_DIR/commands|commands" \
    "$PLUGIN_ROOT/scripts|$HARNESS_DIR/scripts|scripts" \
    "$PLUGIN_ROOT/workflows|$HARNESS_DIR/workflows|workflows" \
    "$PLUGIN_ROOT/workflows|$TOP/.claude/workflows|workflows@claude"
}

_baseline_lookup() {
  # $1 = 基线 key（<前缀>/<相对路径>）；输出上次同步时的 checksum，无记录输出空
  [ -f "${BASELINE_FILE:-}" ] || return 0
  awk -F'|' -v k="$1" '$2 == k { print $1; exit }' "$BASELINE_FILE" 2>/dev/null
}

_write_mirror_baseline() {
  # 首会话脚手架成功后立即记录基线：仅记录「项目侧内容 = plugin 版」的文件
  # （cp -rn 保留下来的既存异版文件不记录 → 后续 drift-sync 按保守初始化视同定制跳过）
  _detect_checksum_tool
  if [ -z "$CHECKSUM_TOOL" ]; then
    log_warn "未找到 checksum 工具（sha256sum/shasum/cksum），跳过镜像基线记录（下次 drift-sync 按保守初始化处理）"
    return 0
  fi
  BASELINE_FILE="$STATE_DIR/.mirror_baseline"
  local tmp pair rest src dst label f rel plugin_sum dst_sum
  tmp="$(mktemp "${TMPDIR:-/tmp}/harness_mirror_baseline.XXXXXX" 2>/dev/null)" || {
    log_warn "mktemp 失败，跳过镜像基线记录"
    return 0
  }
  while IFS= read -r pair; do
    src="${pair%%|*}"; rest="${pair#*|}"; dst="${rest%%|*}"; label="${rest#*|}"
    [ -d "$src" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel="${f#$src/}"
      plugin_sum="$(_file_checksum "$f")"
      [ -n "$plugin_sum" ] || continue
      if [ -f "$dst/$rel" ]; then
        dst_sum="$(_file_checksum "$dst/$rel")"
        [ "$dst_sum" = "$plugin_sum" ] && echo "$plugin_sum|$label/$rel" >> "$tmp"
      fi
    done < <(find "$src" -type f 2>/dev/null)
  done < <(_mirror_pairs)
  mkdir -p "$STATE_DIR" 2>/dev/null
  # 自忽略：STATE_DIR 现项目本地（ADR-016），幂等写 `*` 防运行时哨兵/日志被 commit（不依赖消费方根 .gitignore）
  [ -f "$STATE_DIR/.gitignore" ] || printf '*\n' > "$STATE_DIR/.gitignore" 2>/dev/null
  if mv -f "$tmp" "$BASELINE_FILE" 2>/dev/null; then
    log_info "✅ 镜像基线已记录：$BASELINE_FILE"
  else
    log_warn "镜像基线写入失败（$BASELINE_FILE），下次 drift-sync 按保守初始化处理"
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# ------------------------------------------------------------
# opt-out auto-bootstrap（ADR-015 · feat-firstrun-auto-bootstrap-20260705 翻转父卡 opt-in）
# 默认 enabled（首会话默认自动 bootstrap · 无需任何开关）；仅显式关闭时 disabled——
#   env HARNESS_AUTO_BOOTSTRAP ∈ {0,false}（大小写不敏感）∨ config `bootstrap.auto: false`。
# retry 路径附加 .bootstrap_attempted 前置门（M-2c · 存量 pre-upgrade 项目零追溯 · AC-5a）；
# 任何失败仅 log_warn 且恒 return 0（fail-open · AC-4），
# 且不影响 .scaffold_initialized 落盘语义（B-3 哨兵独立）。
# ------------------------------------------------------------

_auto_bootstrap_enabled() {
  # 2 子句 opt-out 规则（M-1a · ADR-015 · 关信号命中即关，否则 enabled 默认开）：
  #   ① env HARNESS_AUTO_BOOTSTRAP ∈ {0,false}（大小写不敏感）→ disabled；
  #   ② env 非上述关值时，HARNESS_CONFIG.yaml 含单行键 `bootstrap.auto: false`
  #      （grep 单行解析、bash 3.2 兼容、文件缺失即视为未设；容忍前导空白 /
  #      键冒号前空白 / 行尾注释）→ disabled。
  #   矛盾输入 env=1 + config=false → disabled（显式持久关 > 冗余 env=1 · 向关信号倒）。
  # ⚠ 等价锚定（同构规则单一真相指认 · 承 R4-02）：本函数与
  #   session_start_bootstrap_hint.sh 的 switch_on 块实现**同一条 2 子句规则、逐字同构**
  #   （同一组关值 {0,false} 大小写不敏感 + 同一 config false 正则 + 同一子句求值顺序）
  #   ——「一侧拉起、另一侧拒绝接力」的半开态按构造不存在（AC-6）。两文件无法共享
  #   函数，任一侧改动本规则时必须逐字同步另一侧。
  local _env_val
  _env_val="$(printf '%s' "${HARNESS_AUTO_BOOTSTRAP:-}" | tr '[:upper:]' '[:lower:]')"
  case "$_env_val" in
    0|false) return 1 ;;
  esac
  if [ -f "$TOP/HARNESS_CONFIG.yaml" ] \
     && grep -E -q '^[[:space:]]*bootstrap\.auto[[:space:]]*:[[:space:]]*false[[:space:]]*(#.*)?$' \
          "$TOP/HARNESS_CONFIG.yaml" 2>/dev/null; then
    return 1
  fi
  return 0
}

_maybe_auto_bootstrap() {
  # $1 = 触发场景（first-run / retry）· 语义载荷（M-2c · ADR-015，非仅日志）：
  #   first-run → 确定发起时落 $STATE_DIR/.bootstrap_attempted 持久标记，不查门；
  #   retry     → 查 .bootstrap_attempted 前置门（缺失 = 存量 pre-upgrade 项目，
  #               不发起 · AC-5a 零追溯），不落标记。
  # 判据：谓词 enabled（opt-out 默认开）+ .bootstrap_done 缺失（done 仅 T1 exit 0 落）
  #       + [仅 retry] .bootstrap_attempted 存在（M-2c 前置门）
  #       + .bootstrap_running 缺失或其 pid 已死（后台真在跑才不重复拉起 · R4-01）。
  _auto_bootstrap_enabled || return 0
  [ -f "$STATE_DIR/.bootstrap_done" ] && return 0
  if [ "$1" = "retry" ] && [ ! -f "$STATE_DIR/.bootstrap_attempted" ]; then
    log_info "auto-bootstrap（retry）：未检测到 .bootstrap_attempted（存量项目零追溯 · ADR-015），跳过 auto-bootstrap"
    return 0
  fi
  if [ -f "$STATE_DIR/.bootstrap_running" ]; then
    # R4-01 死锁自愈：哨兵唯一清理点是 T1 finish()，脚本无 trap——后台子进程被
    # SIGKILL/机器重启/杀进程组时哨兵永久残留；仅按存在性判断会把 B 路径重试判据
    # 永久短路。故与 hint hook（session_start_bootstrap_hint.sh 分支 A · kill -0）
    # 同口径判 pid 存活：读哨兵首行 pid，存活 → 不重复拉起；已死/为空 → 清除残留
    # 哨兵并视作未在运行，照常走拉起路径（--background 会重写哨兵，自愈闭环）。
    local _bs_pid
    _bs_pid="$(head -1 "$STATE_DIR/.bootstrap_running" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$_bs_pid" ] && kill -0 "$_bs_pid" 2>/dev/null; then
      log_info "auto-bootstrap（$1）：后台任务仍在执行（pid=$_bs_pid · $STATE_DIR/.bootstrap_running），本会话不重复拉起"
      return 0
    fi
    rm -f "$STATE_DIR/.bootstrap_running" 2>/dev/null
    log_info "auto-bootstrap（$1）：检测到残留 .bootstrap_running（pid=${_bs_pid:-空} 已死），已清除残留哨兵，按未运行继续"
  fi

  # 定位 T1 脚本（既有回退链风格）：CLAUDE_PLUGIN_ROOT/hooks（消费方安装态）
  # → $TOP/plugins/harness-core/hooks（本仓开发态）→ 全不命中 warning 跳过不阻断
  local bootstrap_sh=""
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/harness_bootstrap.sh" ]; then
    bootstrap_sh="${CLAUDE_PLUGIN_ROOT}/hooks/harness_bootstrap.sh"
  elif [ -f "$TOP/plugins/harness-core/hooks/harness_bootstrap.sh" ]; then
    bootstrap_sh="$TOP/plugins/harness-core/hooks/harness_bootstrap.sh"
  fi
  if [ -z "$bootstrap_sh" ]; then
    log_warn "auto-bootstrap（$1）：未找到 harness_bootstrap.sh（CLAUDE_PLUGIN_ROOT/hooks 与 plugins/harness-core/hooks 均无），跳过；可手动运行 /harness-core:bootstrap"
    return 0
  fi

  # M-2c：first-run 确定要发起时（已定位到脚本、调用之前）落 .bootstrap_attempted
  # 持久标记（独立于成败、永不自动清理 · retry 前置门的唯一证据）。落标记失败不阻断、
  # 照常发起——标记是零回归门证据而非功能前提（2>/dev/null 吞错）；retry 路径不落
  # 标记（「曾在 first-run 发起过」语义纯净）。
  if [ "$1" = "first-run" ]; then
    mkdir -p "$STATE_DIR" 2>/dev/null
    [ -f "$STATE_DIR/.gitignore" ] || printf '*\n' > "$STATE_DIR/.gitignore" 2>/dev/null  # 自忽略（ADR-016）
    touch "$STATE_DIR/.bootstrap_attempted" 2>/dev/null
  fi

  # B-4/F-3 后台化：--background 内部 nohup 自后台化（重活全在子进程），父进程秒退
  # 不占 SessionStart 60s 预算；日志落 $STATE_DIR/bootstrap.log，结果由
  # .bootstrap_done/.bootstrap_failed 哨兵承载，下会话 hint hook（T4）接力。
  # --yes = 首会话默认授权（opt-out 逃生阀关闭前 · ADR-015）。吞掉脚本非零码（T1 退出码
  # 是诊断信号非 hook 语义），本 hook 恒 exit 0（AC-4）；stdout 并入 stderr 保持 hook stdout 干净。
  log_info "auto-bootstrap（$1）：默认开（ADR-015），后台启动 bootstrap（日志：$STATE_DIR/bootstrap.log）"
  if ! bash "$bootstrap_sh" --yes --background >&2; then
    log_warn "auto-bootstrap（$1）：后台启动失败（非阻断），下会话将重试；可手动运行 /harness-core:bootstrap"
  fi
  return 0
}

# ============================================================
# 函数：新项目脚手架安装（须在主流程前定义）
# ============================================================

_scaffold_new_project() {
  log_info "检测到新 Harness 项目（.harness/changes/ 不存在），开始脚手架安装..."

  local had_error=0

  # 1. 复制 skills 目录
  if [ -d "$PLUGIN_SKILLS" ]; then
    mkdir -p "$SKILLS_DIR"
    if cp -rn "$PLUGIN_SKILLS/." "$SKILLS_DIR/" 2>/dev/null; then
      log_info "✅ skills 已安装到 $SKILLS_DIR/"
    else
      log_warn "skills 安装失败（cp -rn 报错），可能部分文件已存在"
      had_error=1
    fi
  else
    log_warn "plugin skills 目录不存在（$PLUGIN_SKILLS），跳过"
  fi

  # 2. 复制 agents 目录
  if [ -d "$PLUGIN_AGENTS" ]; then
    mkdir -p "$AGENTS_DIR"
    if cp -rn "$PLUGIN_AGENTS/." "$AGENTS_DIR/" 2>/dev/null; then
      log_info "✅ agents 已安装到 $AGENTS_DIR/"
    else
      log_warn "agents 安装失败"
      had_error=1
    fi
  fi

  # 3. 复制 rules 目录
  if [ -d "$PLUGIN_RULES" ]; then
    mkdir -p "$RULES_DIR"
    if cp -rn "$PLUGIN_RULES/." "$RULES_DIR/" 2>/dev/null; then
      log_info "✅ rules 已安装到 $RULES_DIR/"
    else
      log_warn "rules 安装失败"
      had_error=1
    fi
  fi

  # 4. 落盘 changes/ 目录结构（含 _TEMPLATE）
  mkdir -p "$CHANGES_DIR"
  # 优先从 plugin 自身携带的 _TEMPLATE；次选本仓 .harness/changes/_TEMPLATE
  local template_src=""
  if [ -d "$PLUGIN_ROOT/_template/_TEMPLATE" ]; then
    template_src="$PLUGIN_ROOT/_template/_TEMPLATE"
  elif [ -d "$TOP/.harness/changes/_TEMPLATE" ]; then
    template_src="$TOP/.harness/changes/_TEMPLATE"
  fi

  if [ -n "$template_src" ] && [ -d "$template_src" ]; then
    if cp -rn "$template_src" "$CHANGES_DIR/_TEMPLATE" 2>/dev/null; then
      log_info "✅ _TEMPLATE 已落盘到 $CHANGES_DIR/_TEMPLATE"
    else
      log_warn "_TEMPLATE 落盘失败（目录已存在或权限问题）"
    fi
  else
    # 创建最小 _TEMPLATE 骨架
    mkdir -p "$CHANGES_DIR/_TEMPLATE/request_analysis"
    log_info "✅ 最小 _TEMPLATE 骨架已创建"
  fi

  # 5.（已撤 · ADR-013 裁决②）hooks → .harness/hooks/ 副本不再落盘：
  #    hooks.json 已注册 ${CLAUDE_PLUGIN_ROOT}/hooks/* 在 plugin 缓存内直接执行，副本纯冗余。
  #    存量项目残留留置不删，迁移提示见 plugins/README.md。

  # 6. 复制 commands 到 .harness/commands/（只读镜像面 · 供非 Claude 工具消费）
  if [ -d "$PLUGIN_ROOT/commands" ]; then
    mkdir -p "$HARNESS_DIR/commands"
    if cp -rn "$PLUGIN_ROOT/commands/." "$HARNESS_DIR/commands/" 2>/dev/null; then
      log_info "✅ commands 已安装到 $HARNESS_DIR/commands/"
    else
      log_warn "commands 安装失败"
      had_error=1
    fi
  fi

  # 6b. 复制 scripts 到 .harness/scripts/（statusline/list_flows + lib · 与 _mirror_pairs 第 7 组同口径 · feat-plugin-display-parity）
  if [ -d "$PLUGIN_ROOT/scripts" ]; then
    mkdir -p "$HARNESS_DIR/scripts"
    if cp -rn "$PLUGIN_ROOT/scripts/." "$HARNESS_DIR/scripts/" 2>/dev/null; then
      log_info "✅ scripts 已安装到 $HARNESS_DIR/scripts/"
    else
      log_warn "scripts 安装失败"
      had_error=1
    fi
  fi

  # 7. 复制 workflows 到 .harness/workflows/
  if [ -d "$PLUGIN_ROOT/workflows" ]; then
    mkdir -p "$HARNESS_DIR/workflows"
    if cp -rn "$PLUGIN_ROOT/workflows/." "$HARNESS_DIR/workflows/" 2>/dev/null; then
      log_info "✅ workflows 已安装到 $HARNESS_DIR/workflows/"
    else
      log_warn "workflows 安装失败"
      had_error=1
    fi
  fi

  # 7b. 同步 workflows 到 .claude/workflows/（Claude Code 运行时读取路径）
  if [ -d "$PLUGIN_ROOT/workflows" ]; then
    mkdir -p "$TOP/.claude/workflows"
    cp -rn "$PLUGIN_ROOT/workflows/." "$TOP/.claude/workflows/" 2>/dev/null || true
    log_info "✅ workflows 已同步到 .claude/workflows/"
  fi

  # 8. 提示用户创建 CLAUDE.md
  if [ ! -f "$TOP/CLAUDE.md" ]; then
    log_info ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "📋 Harness 项目初始化完成！"
    log_info ""
    log_info "下一步：请创建 CLAUDE.md 以激活 Harness 编排中枢。"
    log_info "参考模板：$PLUGIN_ROOT/CLAUDE.md.template"
    log_info "（或复制 .harness/agents/application-owner.md 的注释段）"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  fi

  # 9.（已撤 · ADR-013 裁决①）commands → .claude/commands/ 二次同步不再产生：
  #    官方 loader 以命名空间 /harness-core:* 原生加载 commands，平铺副本与之撞车且脱离更新链。
  #    存量项目残留留置不删，迁移提示见 plugins/README.md。

  if [ "$had_error" -eq 0 ]; then
    # 标记首次运行完成 + 记录镜像基线（drift-sync 定制保护的比对起点 · 裁决⑥）
    mkdir -p "$STATE_DIR"
    [ -f "$STATE_DIR/.gitignore" ] || printf '*\n' > "$STATE_DIR/.gitignore" 2>/dev/null  # 自忽略（ADR-016）
    touch "$STATE_DIR/.scaffold_initialized"
    _write_mirror_baseline
    log_info "脚手架安装完成 ✅"
  else
    log_warn "脚手架安装部分完成（有警告），请检查上方日志；本次不落哨兵，将于下会话重试"
  fi

  # auto-bootstrap first-run（opt-out 默认开 · ADR-015；F-6 挂函数体尾部）：
  # 谓词默认 enabled（逃生阀显式关闭才退出）→ 落 .bootstrap_attempted 后后台执行
  # bootstrap；成败均不影响上方 .scaffold_initialized 落盘语义（B-3 · AC-4）
  _maybe_auto_bootstrap "first-run"
}

# ============================================================
# 函数：存量项目镜像单向自动同步 drift-sync（须在主流程前定义）
# ADR-013 裁决③⑤⑥ + §3 覆盖边界硬条款表（spec Q2 决议落地）：
#   - 权威源恒为 plugin 缓存（单向）；内容级 checksum 比对替代数文件个数
#   - 三方判定（裁决⑥ 方案 a）：项目=plugin → 已新鲜跳过；项目≠plugin 且=基线 → 安全覆盖刷新；
#     项目≠plugin 且≠基线（含无基线记录的既存异版 · 保守初始化）→ 视同定制告警跳过；
#     项目文件缺失 → 自动复活（裁决⑤ 镜像件删除=漂移）
#   - 写入仅限镜像件路径；_TEMPLATE=no-clobber（整体缺失可补缺、存在永不覆盖）；
#     .harness/changes/**（_TEMPLATE 外）与 .harness/state（基线文件除外）零写入
#   - fail-open：任何失败仅 log_warn、恒 return 0；收敛后下次会话零写入（幂等）
# ============================================================

_drift_sync() {
  if [ ! -d "$PLUGIN_ROOT" ]; then
    log_warn "plugin 根路径不存在（$PLUGIN_ROOT），跳过 drift-sync"
    return 0
  fi

  _detect_checksum_tool
  if [ -z "$CHECKSUM_TOOL" ]; then
    log_warn "未找到 checksum 工具（sha256sum/shasum/cksum），跳过 drift-sync"
    return 0
  fi

  BASELINE_FILE="$STATE_DIR/.mirror_baseline"
  local tmp pair rest src dst label f rel key plugin_sum dst_sum base_sum
  local refreshed=0 revived=0 skipped=0
  tmp="$(mktemp "${TMPDIR:-/tmp}/harness_mirror_baseline.XXXXXX" 2>/dev/null)" || {
    log_warn "mktemp 失败，跳过 drift-sync"
    return 0
  }

  while IFS= read -r pair; do
    src="${pair%%|*}"; rest="${pair#*|}"; dst="${rest%%|*}"; label="${rest#*|}"
    [ -d "$src" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel="${f#$src/}"
      key="$label/$rel"
      plugin_sum="$(_file_checksum "$f")"
      [ -n "$plugin_sum" ] || continue
      if [ ! -f "$dst/$rel" ]; then
        # 漂移·删除形态 → 自动复活（裁决⑤ 镜像件）
        mkdir -p "$(dirname "$dst/$rel")" 2>/dev/null
        if cp "$f" "$dst/$rel" 2>/dev/null; then
          revived=$((revived + 1))
          echo "$plugin_sum|$key" >> "$tmp"
        else
          log_warn "drift-sync 复活失败：$dst/$rel"
        fi
      else
        dst_sum="$(_file_checksum "$dst/$rel")"
        if [ "$dst_sum" = "$plugin_sum" ]; then
          # 已新鲜，零写入
          echo "$plugin_sum|$key" >> "$tmp"
        else
          base_sum="$(_baseline_lookup "$key")"
          if [ -n "$base_sum" ] && [ "$dst_sum" = "$base_sum" ]; then
            # 本地=上次同步版、plugin 有更新 → 安全覆盖刷新
            if cp "$f" "$dst/$rel" 2>/dev/null; then
              refreshed=$((refreshed + 1))
              echo "$plugin_sum|$key" >> "$tmp"
            else
              log_warn "drift-sync 刷新失败：$dst/$rel"
              echo "$base_sum|$key" >> "$tmp"
            fi
          else
            # 本地≠基线（或无基线记录 · 保守初始化）→ 视同定制，告警跳过（永不静默冲掉定制）
            skipped=$((skipped + 1))
            log_warn "检测到本地定制，跳过刷新：$dst/$rel（确认放弃定制可运行 /session-start --upgrade 强制刷新）"
            if [ -n "$base_sum" ]; then
              echo "$base_sum|$key" >> "$tmp"
            fi
          fi
        fi
      fi
    done < <(find "$src" -type f 2>/dev/null)
  done < <(_mirror_pairs)

  # _TEMPLATE 补缺（no-clobber：整体缺失可补齐、存在永不覆盖 · ADR-013 §3）
  if [ -d "$CHANGES_DIR" ] && [ ! -d "$CHANGES_DIR/_TEMPLATE" ] && [ -d "$PLUGIN_ROOT/_template/_TEMPLATE" ]; then
    if cp -rn "$PLUGIN_ROOT/_template/_TEMPLATE" "$CHANGES_DIR/_TEMPLATE" 2>/dev/null; then
      log_info "✅ _TEMPLATE 整体缺失，已从 plugin 补缺"
    else
      log_warn "_TEMPLATE 补缺失败"
    fi
  fi

  # 基线收敛写入（内容不变则不重写，保证收敛后零写入幂等）
  mkdir -p "$STATE_DIR" 2>/dev/null
  [ -f "$STATE_DIR/.gitignore" ] || printf '*\n' > "$STATE_DIR/.gitignore" 2>/dev/null  # 自忽略（ADR-016）
  if [ -f "$BASELINE_FILE" ] && cmp -s "$tmp" "$BASELINE_FILE" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
  else
    if ! mv -f "$tmp" "$BASELINE_FILE" 2>/dev/null; then
      log_warn "镜像基线写入失败（$BASELINE_FILE）"
      rm -f "$tmp" 2>/dev/null
    fi
  fi

  if [ "$refreshed" -gt 0 ] || [ "$revived" -gt 0 ] || [ "$skipped" -gt 0 ]; then
    log_info "drift-sync 完成：刷新 ${refreshed} · 复活 ${revived} · 定制跳过 ${skipped}（权威源=plugin 缓存 · 单向）"
  fi

  # auto-bootstrap 失败重试（opt-out 默认开 · ADR-015；F-6 挂函数体尾部）：
  # 谓词 enabled + .bootstrap_done 缺失 + .bootstrap_attempted 存在（M-2c 前置门 ·
  # 存量 pre-upgrade 项目零追溯 AC-5a）+ .bootstrap_running 缺失或 pid 已死（R4-01）
  # → 重跑（判据在 _maybe_auto_bootstrap 内）
  _maybe_auto_bootstrap "retry"
  return 0
}

# ============================================================
# 守卫：定位仓库根
# ============================================================

TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$TOP" ]; then
  exit 0
fi
cd "$TOP" || exit 0

# ============================================================
# 路径定义（须在所有守卫之前，供 _drift_sync 使用）
# ============================================================

HARNESS_DIR="$TOP/.harness"
CHANGES_DIR="$HARNESS_DIR/changes"
SKILLS_DIR="$HARNESS_DIR/skills"
AGENTS_DIR="$HARNESS_DIR/agents"
RULES_DIR="$HARNESS_DIR/rules"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  if [ -d "$TOP/plugins/harness-core" ]; then
    PLUGIN_ROOT="$TOP/plugins/harness-core"
  else
    log_warn "CLAUDE_PLUGIN_ROOT 未设置且无法推断 plugin 根路径，跳过脚手架安装"
    exit 0
  fi
fi

PLUGIN_SKILLS="$PLUGIN_ROOT/skills"
PLUGIN_AGENTS="$PLUGIN_ROOT/agents"
PLUGIN_RULES="$PLUGIN_ROOT/rules"

# ============================================================
# first-run 守卫（T2 · fix-plugin-self-rebuild)
# 首次会话运行全量重建，后续跳过（项目内 .harness/state/.scaffold_initialized · ADR-016）
# ============================================================

STATE_DIR="${HARNESS_STATE_DIR:-$TOP/.harness/state}"
if [ -f "$STATE_DIR/.scaffold_initialized" ]; then
  # 已初始化，走镜像单向自动同步后退出（路径变量已就绪）
  _drift_sync
  exit 0
fi

# ============================================================
# 守卫：确认这是一个 Harness 项目
# 无 HARNESS_CONFIG.yaml 时仍然触发全量初始化（新用户场景）
# ============================================================

if [ ! -f "$TOP/HARNESS_CONFIG.yaml" ]; then
  # 无配置文件 → 新项目，触发全量初始化
  _scaffold_new_project
  exit 0
fi

# ============================================================
# 主流程分支判断
# ============================================================

if [ -d "$CHANGES_DIR" ]; then
  _drift_sync
else
  _scaffold_new_project
fi

exit 0
