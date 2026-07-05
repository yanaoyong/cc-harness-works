#!/usr/bin/env bash
# harness_pin_to_project.sh — opt-in 分发声明写入（/harness-core:pin-to-project 的共享实现）
#
# 职责：项目主人主动运行时，把 marketplace（cc-harness-works）+ 本项目已启用插件声明
#       JSON-safe 合并写进消费项目 tracked 的 .claude/settings.json（随 git 分发给队友，
#       免去队友手工 /plugin marketplace add + /plugin install）。
#
# 语义边界：
#   - opt-in：仅在项目主人主动运行本脚本时写入；不注册任何 SessionStart/Stop hook、不自动触发。
#   - 供应链知情：写声明入库 = 任何克隆并信任该仓库的人会被 CC 提示安装此 marketplace + 插件，
#     是项目主人主动的分发决定（运行时 stderr echo + README 段双落点）。
#   - 版本局限（R-1）：只声明启用不锁 sha/版本；克隆者装 marketplace 当前 HEAD 版本。
#   - 安全：不写任何 key/token；API key 一律走环境变量、不入库。
#
# enable 口径（R-2）：installed_plugins.json 中某 <plugin>@<marketplace> 键存在
#   projectPath 与本仓库根「大小写敏感、realpath 规范化后精确匹配」的 install 记录，
#   即视为本项目已启用该插件 → 镜像进 enabledPlugins。
#
# 测试缝（供 stage-5 单测，覆盖默认路径 · 不碰真实 ~/.claude）：
#   PIN_INSTALLED_PLUGINS  默认 $HOME/.claude/plugins/installed_plugins.json
#   PIN_SETTINGS_TARGET    默认 $TOP/.claude/settings.json
#   PIN_REPO_ROOT          默认 $TOP（projectPath 匹配基准）
#   --dry-run              只打印将写入的 JSON 声明与匹配键，不落盘
#
# 退出码表（见 command playbook / coding_report）：
#   0  成功写入，或 --dry-run 展示完成
#   2  非 git 仓库 / 用法错误（未知参数）
#   3  installed_plugins.json 缺失 / 非法 JSON / 顶层非 dict（R-4：拒绝臆造 enabledPlugins）
#   4  无 python3 且目标 settings.json 已存在 → 放弃合并（留痕，不冒险文本拼接破坏 JSON）
#   6  目标 settings.json 非法 JSON / 非对象 → 拒绝触碰
#   7  原子写盘失败
#
# bash 3.2 兼容：不使用 declare -A / mapfile / readarray / realpath(1)。
set -uo pipefail

PREFIX="[harness:pin-to-project]"
log_info() { echo "$PREFIX $*" >&2; }
log_warn() { echo "$PREFIX ⚠️  $*" >&2; }

# ------------------------------------------------------------
# 参数解析
# ------------------------------------------------------------
DRY_RUN=0
for _arg in "$@"; do
  case "$_arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      echo "usage: harness_pin_to_project.sh [--dry-run]"
      exit 2
      ;;
    *)
      log_warn "未知参数：$_arg（仅支持 --dry-run）"
      exit 2
      ;;
  esac
done

# ------------------------------------------------------------
# 定位仓库根 + 非 git 拒绝
# ------------------------------------------------------------
TOP="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log_warn "当前目录不在 git 仓库内（$TOP）；pin-to-project 需在目标项目 git 仓库根内运行"
  exit 2
fi

# ------------------------------------------------------------
# 测试缝：可覆盖默认路径
# ------------------------------------------------------------
INSTALLED="${PIN_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"
SETTINGS_TARGET="${PIN_SETTINGS_TARGET:-$TOP/.claude/settings.json}"
REPO_ROOT="${PIN_REPO_ROOT:-$TOP}"

# 供应链知情提示文案（运行时 stderr echo · AC-4b）
SUPPLY_CHAIN_NOTE="供应链提示：把该声明写入 tracked .claude/settings.json = 任何克隆并信任本仓库的人会被 Claude Code 提示安装此 marketplace（cc-harness-works）+ 已启用插件——这是你作为项目主人主动的分发决定。"

# ============================================================
# 主流程
# ============================================================
if command -v python3 >/dev/null 2>&1; then

  # ---- T2：收集 projectPath 精确匹配的 <plugin>@<marketplace> 键 ----
  MATCHED="$(PIN_INSTALLED="$INSTALLED" PIN_REPO="$REPO_ROOT" python3 - <<'PYEOF'
import json, os, sys

path = os.environ["PIN_INSTALLED"]
repo = os.environ["PIN_REPO"]
PREFIX = "[harness:pin-to-project] ⚠️ "

# R-4：缺失 / 非法 JSON / 顶层非 dict → 拒绝臆造，exit 3
if not os.path.exists(path):
    sys.stderr.write(PREFIX + "未找到 installed_plugins.json（%s）；无法确定本项目启用集，拒绝臆造 enabledPlugins\n" % path)
    sys.exit(3)
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.stderr.write(PREFIX + "installed_plugins.json 非法 JSON（%s）；拒绝臆造 enabledPlugins\n" % path)
    sys.exit(3)
if not isinstance(data, dict):
    sys.stderr.write(PREFIX + "installed_plugins.json 顶层非 dict（%s）；拒绝臆造 enabledPlugins\n" % path)
    sys.exit(3)

plugins = data.get("plugins")
repo_real = os.path.realpath(repo)

matched = []
if isinstance(plugins, dict):
    for key, records in plugins.items():
        if not isinstance(records, list):
            continue
        for rec in records:
            if not isinstance(rec, dict):
                continue
            pp = rec.get("projectPath")
            if not isinstance(pp, str) or pp == "":
                continue
            # 大小写敏感、realpath 规范化（去 symlink/尾斜杠/..）后精确 ==
            if os.path.realpath(pp) == repo_real:
                matched.append(key)
                break  # 该键命中一次即足够（R-2）

# R-3：零匹配 → stderr 明文提示，不产生 enabledPlugins（stdout 留空）
if not matched:
    sys.stderr.write(PREFIX + "未找到本项目（%s）的插件启用记录，可能未装插件 / projectPath 不一致；仅写 marketplace 声明，enabledPlugins 段留空不动\n" % repo)

for k in matched:
    sys.stdout.write(k + "\n")
sys.exit(0)
PYEOF
)"
  _collect_rc=$?
  if [ "$_collect_rc" -eq 3 ]; then
    exit 3
  fi

  # ---- dry-run：只展示将写入的声明 + 匹配键，不落盘 ----
  if [ "$DRY_RUN" -eq 1 ]; then
    log_info "dry-run：以下为将合并进 $SETTINGS_TARGET 的声明（不落盘）"
    PIN_MATCHED="$MATCHED" python3 - <<'PYEOF'
import json, os, sys
matched = [k for k in os.environ.get("PIN_MATCHED", "").split("\n") if k]
preview = {
    "extraKnownMarketplaces": {
        "cc-harness-works": {"source": {"source": "github", "repo": "yanaoyong/cc-harness-works"}}
    }
}
if matched:
    preview["enabledPlugins"] = {k: True for k in matched}
sys.stdout.write(json.dumps(preview, indent=2, ensure_ascii=False) + "\n")
PYEOF
    exit 0
  fi

  # ---- 非 dry-run：先打供应链提示，再 JSON-safe 合并落盘 ----
  log_warn "$SUPPLY_CHAIN_NOTE"

  PIN_MATCHED="$MATCHED" python3 - "$SETTINGS_TARGET" <<'PYEOF'
import json, os, sys

path = sys.argv[1]
matched = [k for k in os.environ.get("PIN_MATCHED", "").split("\n") if k]

# 读现有目标（不存在 → 起始 {}）；非法 JSON / 非 dict → exit 2（拒绝触碰）
data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        sys.exit(2)
    if not isinstance(data, dict):
        sys.exit(2)

# extraKnownMarketplaces 浅合并（保留他人其它 marketplace 条目）
mk = data.get("extraKnownMarketplaces")
if not isinstance(mk, dict):
    mk = {}
mk["cc-harness-works"] = {"source": {"source": "github", "repo": "yanaoyong/cc-harness-works"}}
data["extraKnownMarketplaces"] = mk

# enabledPlugins 浅合并（保留他人已有条目）；零匹配则不产生该段（R-3）
if matched:
    ep = data.get("enabledPlugins")
    if not isinstance(ep, dict):
        ep = {}
    for k in matched:
        ep[k] = True
    data["enabledPlugins"] = ep

# 原子落盘（稳定序列化，保证幂等 byte 级一致）
tmp = path + ".harness-pin.tmp"
try:
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
except Exception:
    try:
        os.path.exists(tmp) and os.remove(tmp)
    except Exception:
        pass
    sys.exit(3)
sys.exit(0)
PYEOF
  _merge_rc=$?
  if [ "$_merge_rc" -eq 0 ]; then
    if [ -n "$MATCHED" ]; then
      log_info "已写入 $SETTINGS_TARGET：extraKnownMarketplaces.cc-harness-works + enabledPlugins（$(printf '%s' "$MATCHED" | grep -c . ) 个匹配键）"
    else
      log_info "已写入 $SETTINGS_TARGET：extraKnownMarketplaces.cc-harness-works（零匹配，enabledPlugins 段未产生）"
    fi
    exit 0
  elif [ "$_merge_rc" -eq 2 ]; then
    log_warn "目标 settings.json 非法 JSON（或非对象），拒绝触碰；请人工检查 $SETTINGS_TARGET"
    exit 6
  else
    log_warn "settings.json 原子写盘失败（python3 rc=$_merge_rc）；未改动 $SETTINGS_TARGET"
    exit 7
  fi

else
  # ============================================================
  # 无 python3 降级（三守卫同构 setup_statusline.sh）
  # ============================================================
  if [ "$DRY_RUN" -eq 1 ]; then
    log_warn "无 python3：无法解析 installed_plugins.json 计算 enabledPlugins；以下仅为 marketplace 声明预览"
    cat <<'JSONEOF'
{
  "extraKnownMarketplaces": {
    "cc-harness-works": {
      "source": {
        "source": "github",
        "repo": "yanaoyong/cc-harness-works"
      }
    }
  }
}
JSONEOF
    exit 0
  fi

  log_warn "$SUPPLY_CHAIN_NOTE"

  if [ -f "$SETTINGS_TARGET" ]; then
    log_warn "无 python3 且 $SETTINGS_TARGET 已存在，放弃合并（不冒险文本拼接破坏 JSON）；请安装 python3 后重跑，或人工把 extraKnownMarketplaces.cc-harness-works 合并进去"
    exit 4
  fi

  mkdir -p "$(dirname "$SETTINGS_TARGET")" 2>/dev/null || {
    log_warn "无法创建目标目录，放弃写入"
    exit 7
  }
  cat > "$SETTINGS_TARGET" <<'JSONEOF'
{
  "extraKnownMarketplaces": {
    "cc-harness-works": {
      "source": {
        "source": "github",
        "repo": "yanaoyong/cc-harness-works"
      }
    }
  },
  "enabledPlugins": {}
}
JSONEOF
  if [ $? -eq 0 ]; then
    log_info "已写入全新 $SETTINGS_TARGET（无 python3 · marketplace 声明 + 空 enabledPlugins；enabledPlugins 需 python3 环境重跑补全）"
    exit 0
  else
    log_warn "settings.json 创建失败；未改动 $SETTINGS_TARGET"
    exit 7
  fi
fi
