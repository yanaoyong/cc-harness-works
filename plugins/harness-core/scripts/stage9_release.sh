#!/usr/bin/env bash
# stage9_release.sh —— 阶段 9（发版）执行脚本（变更 chore-ci-baseline-and-stage9-script-20260714 · T3/T4）
#
# 定位：阶段 9 的**执行载体**（非判定器）。把"lockstep 4 文件 6 处版本 bump → 一致性断言 →
#       公有仓 sync 委派 → README heredoc 回退检出保留 → tag 清单准备"这条高度机械、且历史上
#       反复踩坑（lockstep 漏改 / README 回退第 8 次再现）的链路，从模型回合搬进纯 shell 载体
#       （proposal-012 §3④ · 照 stage7_push.sh / stage8_ci.sh 模式）。判定权归**机械断言**；
#       异常一律**即停报出**，绝不自行 auto-rollback / force / 发版（ADR-005 语义不变）。
#
# R4 留痕：经本脚本执行的阶段 9 归类 `owner·script·stage9_release.sh`（见 application-owner.md R4 留痕格式）——
#       与 P0 要堵的 `owner·inline·<理由>` 逃逸有本质区别（脚本化的合法非委派执行）。
#
# 契约（spec AC-10 ~ AC-18 / AC-22 / AC-23）：
#   AC-10 目标版本号 = 唯一必选**位置**入参（缺失 → 报用法非 0 退出，脚本**绝不自行推断/递增**）；
#         公有仓 target 工作副本路径 = sync 环节**必选旗标** `--public-repo`（缺失且未 --skip-sync
#         → 报用法退出，**不推测默认路径**——与版本号禁推测同精神，均属 HITL-4 部署参数域）。
#   AC-11 lockstep 4 文件 6 处 version 字段全部按目标版本推进。断言作用域**限定这 4 个文件**（非全仓——
#         旧版本号广泛出现于 docs/changelog/历史报告，全仓 grep 恒失败）；版本匹配用**锚定正则**、
#         同时覆盖 `"X.Y.Z"` 与 `"~X.Y.Z"` 两形态，引号边界防 `0.8.1` 误配 `0.8.10` 子串误配。
#   AC-12 bump 后自动断言（旧版本残留=0 / 目标版本=6 / jq 逐文件 JSON 合法），作用域与正则同 AC-11；
#         任一不满足 → 报错非 0 退出，**不继续** sync / tag。
#   AC-13 公有仓组装**委派** .harness/scripts/sync_public_marketplace.sh（不在本脚本重复实现白名单/剔除）。
#   AC-14 sync 后在 **target 公有仓工作副本内**（非本仓）diff README.md 与其 git HEAD 版本；检出 heredoc
#         覆盖回退 → 在 target 仓内 `git checkout -- README.md` 恢复手工版（前提：手工 README 已 commit），
#         或即停提示人工——**不静默丢失**手工 README、不 push。前置校验 target 须为 git 仓且 README 已入库。
#   AC-15 push / tag 推送默认**只做核对与清单准备**，绝不默认执行；出仓动作留 DF-007 授权门后由人工执行。
#         本脚本全文不含默认 `git push` / `git push --tags` 动作（文本审查可证）。
#   AC-16 生成 tag 清单（版本 tag 名 + 待推 remote + 待人工执行的命令），脚本不默认 `git push --tags`。
#   AC-17 纯 shell + 既有 git/jq CLI，无 API key、无外部网络引擎（沿用 stage7_push.sh AC-21 模式）。
#   AC-18 R4 留痕类别 `owner·script·stage9_release.sh`（见头部说明）。
#   AC-22 bump 非原子——若某处写入失败或 AC-12 断言不通过，工作树处于"部分 bumped"不一致态；
#         脚本 fail-closed 拦截（**不进入** sync / tag）、stderr **报出哪些文件已改/未改**，
#         残留不一致工作树由**人工** `git checkout -- <lockstep 文件>` 恢复；脚本**不自行 auto-rollback / 不 force**。
#   AC-23 `--dry-run` 下打印计划动作（6 处 bump 目标清单 / sync 委派计划 / tag 清单），**不写任何 lockstep
#         文件、不调用 sync、不 push、不 tag**——真实仓零 mutate（前后 `git status` 零新增 diff）。
#
# 用法：
#   bash .harness/scripts/stage9_release.sh <target_version> \
#     --public-repo <公有仓工作副本目录> \
#     [--remote origin] [--dry-run]
#   bash .harness/scripts/stage9_release.sh <target_version> --skip-sync [--dry-run]
#
# 参数：
#   <target_version>        目标版本号（唯一必选**位置**入参 · 形如 X.Y.Z · 脚本禁推断/递增 · AC-10）
#   --public-repo <dir>     公有分发仓（cc-harness-works）工作副本目录（sync 环节必选 · 缺失且未 --skip-sync 即报用法 · AC-10）
#   --skip-sync             显式跳过公有仓 sync 环节（此时无需 --public-repo）
#   --remote <name>         tag 待推远端名（默认 origin · 仅用于 tag 清单展示，脚本不推 tag）
#   --dry-run               安全模式：打印计划动作，真实仓零 mutate（AC-23）
#   -h | --help             打印本用法
#
# 退出码：
#   0 成功（或 --dry-run 计划打印完成）
#   1 用法/参数错误（缺版本号 / 版本号格式非法 / 缺 --public-repo 且未 --skip-sync / 目标版本==现版本 / bump 前 lockstep 已不一致）
#   2 lockstep 版本一致性断言失败（AC-12 / AC-22 · 报出已改/未改清单）
#   3 sync 前置校验失败（target 非 git 仓 / README 未入库 · AC-14 前置）或 README 回退处置需人工
#   4 sync 委派脚本执行失败
set -uo pipefail

SCRIPT_NAME="stage9_release.sh"

usage() {
  sed -n '2,66p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'   # 头部注释块（至 set -uo pipefail 前一行）
}

log()  { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '[%s] ⚠ %s\n' "$SCRIPT_NAME" "$*" >&2; }
die()  { local code="$1"; shift; printf '[%s] ✗ %s\n' "$SCRIPT_NAME" "$*" >&2; exit "$code"; }

# ---------- 参数解析 ----------
target_version=""
public_repo=""
skip_sync=0
remote="origin"
dry_run=0
positionals=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --public-repo)    public_repo="${2:-}"; shift 2 ;;
    --public-repo=*)  public_repo="${1#--public-repo=}"; shift ;;
    --skip-sync)      skip_sync=1; shift ;;
    --remote)         remote="${2:-}"; shift 2 ;;
    --remote=*)       remote="${1#--remote=}"; shift ;;
    --dry-run)        dry_run=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; while [ "$#" -gt 0 ]; do positionals+=("$1"); shift; done ;;
    -*)               die 1 "未知参数：$1（-h 看用法）" ;;
    *)                positionals+=("$1"); shift ;;
  esac
done

# ---------- AC-10：目标版本号必选位置入参（禁推测/禁递增）----------
if [ "${#positionals[@]}" -eq 0 ]; then
  usage
  die 1 "缺目标版本号（唯一必选位置入参）。脚本**绝不自行推断/递增**版本号（HITL-4 部署参数域 · AC-10）。"
fi
if [ "${#positionals[@]}" -gt 1 ]; then
  die 1 "位置入参多于一个（${positionals[*]}）——只接受单个目标版本号。"
fi
target_version="${positionals[0]}"

# 版本号格式校验（X.Y.Z 严格 · 拒绝空/带 v 前缀/带 ~/非法字符 → 逼调用方给规范值，不做纠错）
if ! printf '%s' "$target_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  die 1 "目标版本号格式非法：'$target_version'（须为 X.Y.Z，如 0.8.8）。脚本不纠错/不猜测。"
fi

# ---------- AC-10：sync 环节 target 路径必选（缺失且未 --skip-sync → 报用法退出，不推测默认路径）----------
if [ "$skip_sync" -eq 0 ] && [ -z "$public_repo" ]; then
  usage
  die 1 "缺 --public-repo（公有仓工作副本目录）——sync 环节必选。脚本**不推测默认路径**（HITL-4 部署参数域 · AC-10）。
  → 确不需要 sync 公有仓，请显式加 --skip-sync。"
fi

# ---------- 定位本仓根 ----------
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die 1 "当前目录不在 git 仓库内"

# ---------- lockstep 4 文件 6 处 ----------
# 落点固定（spec §1 lockstep 铁律 · grep '"version"' 实测 2026-07-14）：
#   marketplace.json:1 处 / harness-core:1 处 / python:2 处（version + ~dep）/ react-vite:2 处（version + ~dep）
LOCKSTEP_FILES=(
  "$repo_root/.claude-plugin/marketplace.json"
  "$repo_root/plugins/harness-core/.claude-plugin/plugin.json"
  "$repo_root/plugins/harness-profile-python/.claude-plugin/plugin.json"
  "$repo_root/plugins/harness-profile-react-vite/.claude-plugin/plugin.json"
)
# 每文件期望的目标版本命中数（AC-11：合计 6）
LOCKSTEP_EXPECT=(1 1 2 2)

for f in "${LOCKSTEP_FILES[@]}"; do
  [ -f "$f" ] || die 1 "lockstep 文件缺失：$f（本仓结构异常，不发版）"
done

# 版本号转义为正则安全形态（点号转义）
esc_ver() { printf '%s' "$1" | sed 's/\./\\./g'; }

# 锚定正则计数：`"(~)?V"` —— 引号边界杜绝 0.8.1 误配 0.8.10 子串（AC-11/AC-12）。
# $1=版本号；$2..=文件列表 → 打印总命中数。
count_version() {
  local v esc total=0 f n
  v="$1"; shift
  esc="$(esc_ver "$v")"
  for f in "$@"; do
    n="$(grep -oE "\"(~)?${esc}\"" "$f" 2>/dev/null | wc -l | tr -d ' ')"
    total=$((total + n))
  done
  printf '%s' "$total"
}
# 单文件命中数（用于 per-file 报告）
count_version_file() {
  local v esc f
  v="$1"; f="$2"
  esc="$(esc_ver "$v")"
  grep -oE "\"(~)?${esc}\"" "$f" 2>/dev/null | wc -l | tr -d ' '
}

# ---------- 侦测现版本 = marketplace.json 权威源 ----------
if command -v jq >/dev/null 2>&1; then
  cur_version="$(jq -r '.metadata.version' "${LOCKSTEP_FILES[0]}" 2>/dev/null)"
else
  # jq 不可用兜底：从 marketplace.json 抓第一个锚定 version 值
  cur_version="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "${LOCKSTEP_FILES[0]}" 2>/dev/null \
                 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
fi
[ -n "$cur_version" ] && [ "$cur_version" != "null" ] \
  || die 1 "无法侦测现版本号（marketplace.json 的 metadata.version 读取失败）——不发版。"

if [ "$cur_version" = "$target_version" ]; then
  die 1 "目标版本（$target_version）与现版本（$cur_version）相同——无需 bump。脚本不做空发版。"
fi

# ---------- bump 前 lockstep 一致性前置校验（防从已破损态发版）----------
# 6 处应当全部 == 现版本；否则工作树 lockstep 已不一致，属既有故障，报出后即停（不 bump）。
pre_bad=()
for i in "${!LOCKSTEP_FILES[@]}"; do
  f="${LOCKSTEP_FILES[$i]}"; want="${LOCKSTEP_EXPECT[$i]}"
  got="$(count_version_file "$cur_version" "$f")"
  [ "$got" = "$want" ] || pre_bad+=("$f（现版本 $cur_version 命中 $got，期望 $want）")
done
pre_cur_total="$(count_version "$cur_version" "${LOCKSTEP_FILES[@]}")"
if [ "${#pre_bad[@]}" -gt 0 ] || [ "$pre_cur_total" != "6" ]; then
  {
    printf '[%s] ✗ bump 前 lockstep 已不一致（现版本 %s 合计命中 %s，期望 6）：\n' "$SCRIPT_NAME" "$cur_version" "$pre_cur_total"
    for b in ${pre_bad[@]+"${pre_bad[@]}"}; do printf '  - %s\n' "$b"; done
    printf '  → 即停，不 bump。请人工核对 4 个 lockstep 文件后再发版（既有故障，非本次 bump 造成）。\n'
  } >&2
  exit 1
fi

log "本仓根：$repo_root"
log "版本推进：$cur_version → $target_version（lockstep 4 文件 6 处）"

# ---------- 计划清单（dry-run 与 real 共用打印）----------
print_bump_plan() {
  log "计划 bump 6 处 version 字段（$cur_version → $target_version）："
  for i in "${!LOCKSTEP_FILES[@]}"; do
    f="${LOCKSTEP_FILES[$i]}"; want="${LOCKSTEP_EXPECT[$i]}"
    printf '  · %s（%s 处）\n' "${f#"$repo_root"/}" "$want"
  done
}
print_sync_plan() {
  if [ "$skip_sync" -eq 1 ]; then
    log "sync 计划：--skip-sync 已指定 → 跳过公有仓 sync 环节。"
  else
    log "sync 计划：委派 .harness/scripts/sync_public_marketplace.sh \"$public_repo\""
    log "           sync 后在 target 仓内 diff README.md vs git HEAD → 检出 heredoc 回退即 checkout 恢复手工版（AC-14）。"
  fi
}
print_tag_plan() {
  local tag="v$target_version"
  log "tag 清单（脚本不推 tag · 出仓动作留 DF-007 授权门后人工执行 · AC-15/16）："
  printf '  · tag 名：%s\n' "$tag"
  printf '  · 待推 remote：%s\n' "$remote"
  printf '  · 待人工执行（授权后）：git tag -a %s -m "release %s" && git push %s %s\n' "$tag" "$target_version" "$remote" "$tag"
}

if [ "$dry_run" -eq 1 ]; then
  log "=== --dry-run：仅打印计划，真实仓零 mutate（AC-23）==="
  print_bump_plan
  print_sync_plan
  print_tag_plan
  log "--dry-run 完成：未写任何 lockstep 文件、未调用 sync、未 push、未 tag。"
  exit 0
fi

# ================= 以下为真实执行路径 =================

# ---------- AC-11：lockstep 6 处机械 bump ----------
# 锚定 sed 替换：`"(~)?OLD"` → `"(~)?NEW"`，`\1` 保留可选的 `~` 前缀（依赖约束形态）。
# 引号边界 + 逐文件作用域，杜绝子串误配与全仓污染。
esc_cur="$(esc_ver "$cur_version")"
print_bump_plan
sed_failed=()
for f in "${LOCKSTEP_FILES[@]}"; do
  if ! sed -i "s/\"\(~\{0,1\}\)${esc_cur}\"/\"\1${target_version}\"/g" "$f" 2>/dev/null; then
    sed_failed+=("$f")
    warn "sed 写入失败：${f#"$repo_root"/}（工作树可能处于部分 bumped 态 · 交由下方断言 fail-closed 处置）"
  fi
done

# ---------- AC-12 / AC-22：bump 后一致性断言（fail-closed · 报出已改/未改）----------
assert_failed=0
report_lines=()
old_total="$(count_version "$cur_version" "${LOCKSTEP_FILES[@]}")"
new_total="$(count_version "$target_version" "${LOCKSTEP_FILES[@]}")"

# 逐文件 per-file 状态（已改/未改）
for i in "${!LOCKSTEP_FILES[@]}"; do
  f="${LOCKSTEP_FILES[$i]}"; want="${LOCKSTEP_EXPECT[$i]}"
  rel="${f#"$repo_root"/}"
  new_hit="$(count_version_file "$target_version" "$f")"
  old_hit="$(count_version_file "$cur_version" "$f")"
  if [ "$new_hit" = "$want" ] && [ "$old_hit" = "0" ]; then
    report_lines+=("  ✓ $rel：已改（新版本 $new_hit/$want · 旧版本残留 0）")
  else
    assert_failed=1
    report_lines+=("  ✗ $rel：未完成（新版本 $new_hit/$want · 旧版本残留 $old_hit）")
  fi
done

# 合计断言（旧=0 / 新=6）
[ "$old_total" = "0" ] || assert_failed=1
[ "$new_total" = "6" ] || assert_failed=1

# jq 逐文件 JSON 合法性（仅在 jq 可用时；不可用则告警但不放行断言的其它维度）
jq_ok=1
if command -v jq >/dev/null 2>&1; then
  for f in "${LOCKSTEP_FILES[@]}"; do
    if ! jq empty "$f" >/dev/null 2>&1; then
      jq_ok=0; assert_failed=1
      report_lines+=("  ✗ ${f#"$repo_root"/}：jq JSON 非法（bump 破坏了 JSON 结构）")
    fi
  done
else
  warn "jq 不可用：跳过 JSON 合法性断言（旧/新版本计数断言仍生效 · CI 环境应装 jq）"
fi

if [ "$assert_failed" -ne 0 ]; then
  {
    printf '[%s] ✗ lockstep 版本一致性断言失败（AC-12 / AC-22 · fail-closed）：\n' "$SCRIPT_NAME"
    printf '    合计：旧版本 %s 残留 %s（期望 0）· 目标版本 %s 命中 %s（期望 6）· jq_ok=%s\n' \
      "$cur_version" "$old_total" "$target_version" "$new_total" "$jq_ok"
    printf '    逐文件已改/未改：\n'
    for l in "${report_lines[@]}"; do printf '  %s\n' "$l"; done
    [ "${#sed_failed[@]}" -gt 0 ] && {
      printf '    sed 写入失败文件：\n'
      for f in "${sed_failed[@]}"; do printf '      - %s\n' "${f#"$repo_root"/}"; done
    }
    printf '  → 工作树处于"部分 bumped"不一致态。脚本 fail-closed 即停：**不进入** sync / tag。\n'
    printf '  → 脚本**不自行 auto-rollback / 不 force**（异常即停不臆测 · AC-22）。\n'
    printf '  → 请人工 `git checkout -- %s` 恢复后重跑。\n' ".claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json"
  } >&2
  exit 2
fi

log "AC-12 断言通过：旧版本残留 0 · 目标版本命中 6 · jq JSON 全部合法。lockstep bump 完成。"
for l in "${report_lines[@]}"; do printf '%s\n' "$l"; done

# ---------- AC-13 / AC-14：公有仓 sync 委派 + README heredoc 回退检出保留 ----------
if [ "$skip_sync" -eq 1 ]; then
  log "--skip-sync：跳过公有仓 sync 环节。"
else
  sync_script="$repo_root/.harness/scripts/sync_public_marketplace.sh"
  [ -f "$sync_script" ] || die 4 "sync 委派脚本缺失：$sync_script"

  # AC-14 前置校验：target 须为 git 仓且 README.md 已入库（否则回退检出无参照 → 即停提示人工，不臆测处置）
  [ -d "$public_repo" ] || die 3 "公有仓工作副本目录不存在：$public_repo（不臆测 · 请人工核对路径）"
  if ! git -C "$public_repo" rev-parse --show-toplevel >/dev/null 2>&1; then
    die 3 "公有仓工作副本不是 git 仓：$public_repo
  → AC-14 README 回退检出依赖 target 的 git HEAD 作参照，无 git 无法安全恢复手工 README。请人工处置。"
  fi
  if ! git -C "$public_repo" ls-files --error-unmatch README.md >/dev/null 2>&1; then
    die 3 "公有仓 $public_repo 内 README.md 未入库（git tracked）——
  → sync 的 heredoc 会覆盖它且无 HEAD 可回退恢复手工版。请先在公有仓 commit 手工 README.md 再发版（AC-14 前置 · 不臆测）。"
  fi

  # AC-13：委派 sync 脚本（不重复实现白名单/剔除逻辑）
  log "委派公有仓组装：$sync_script \"$public_repo\""
  if ! bash "$sync_script" "$public_repo"; then
    die 4 "sync 委派脚本执行失败（详见其输出）。已 bump 的 lockstep 保留，未 push。请人工排查。"
  fi

  # AC-14：sync 后在 target 仓内 diff README.md vs 其 git HEAD → 检出 heredoc 回退即 checkout 恢复手工版
  if git -C "$public_repo" diff --quiet -- README.md 2>/dev/null; then
    log "README 检查：sync 后 target README.md 与 git HEAD 一致（无 heredoc 回退，无需恢复）。"
  else
    warn "检出 sync 的 heredoc 覆盖了 target 手工 README.md（回退坑再现）→ 在 target 仓内 checkout 恢复手工版..."
    if git -C "$public_repo" checkout -- README.md 2>/dev/null; then
      log "README 已恢复：git -C \"$public_repo\" checkout -- README.md（手工版保留，不静默丢失 · AC-14）。"
    else
      die 3 "README.md 检出恢复失败（$public_repo）——**不静默丢失**手工 README。请人工 `git -C \"$public_repo\" checkout -- README.md` 处置。"
    fi
  fi
  log "公有仓 sync 完成（组装 + README 保留处置）。push 留人工/授权门（脚本不 push · AC-15）。"
fi

# ---------- AC-15 / AC-16：tag 清单准备（脚本默认不推 tag，出仓动作留 DF-007 授权门）----------
print_tag_plan
log "DONE：lockstep bump ✓ · sync ✓ · tag 清单已备。出仓动作（push / push --tags）须经 HITL-4/DF-007 授权后人工执行——本脚本默认不 push、不 tag。"
exit 0
