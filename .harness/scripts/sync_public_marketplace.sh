#!/usr/bin/env bash
# sync_public_marketplace.sh — 把私有开发仓的可分发子集组装到公有分发仓工作副本（feat-public-marketplace-distribution · AC-3）。
#   仅本地组装 + 幂等复制 + 打印后续人工命令；绝不执行 git / gh / push / 建仓（对外动作留人工/阶段9 显式执行）。
# 用法:
#   bash .harness/scripts/sync_public_marketplace.sh <target_dir>
#     <target_dir> = 公有分发仓（yanaoyong/cc-harness-works）工作副本目录（缺参数报用法退出）。
#   bash .harness/scripts/sync_public_marketplace.sh --print-generated README.md
#     只向 stdout 输出 README 生成结果；不解析/清理/写入 target。
#
# 可分发复制集合的唯一事实源：
#   .harness/config/public_distribution_manifest.json
# 本脚本只消费该 manifest，不另存 plugin/顶层文件白名单。README 正文仍由下方
# public-readme heredoc 生成，其策略与目标路径也登记在 manifest。
#
# 幂等: 复制前先按 manifest 清理 target 内由本脚本管理的目标，再复制/生成。
# 零对外副作用: 不 git init / add / commit / push，不 gh repo create；结尾仅 echo 打印后续人工命令提示。
set -euo pipefail

usage() {
  echo "用法: sync_public_marketplace.sh <target_dir> | --print-generated README.md" >&2
}

# ---------- 入参解析 ----------
if [ "$#" -eq 2 ] && [ "$1" = "--print-generated" ]; then
  PRINT_GENERATED="$2"
elif [ "$#" -eq 1 ]; then
  case "$1" in
    -h|--help) usage; exit 0 ;;
  esac
  PRINT_GENERATED=""
  TARGET_INPUT="$1"
  TARGET="$1"
else
  usage
  exit 2
fi

print_public_readme() {
  cat <<'EOF'
# cc-harness-works

Harness 全生命周期方法论的 Claude Code 插件市场：一套栈无关的 10 阶段 K 流程 + 元流程 M0–M5 骨架，外加可选的栈 profile（Python / React+Vite）。

## 安装

```
/plugin marketplace add yanaoyong/cc-harness-works
/plugin install harness-core@cc-harness-works
```

## 插件清单

| 插件 | 说明 |
|---|---|
| `harness-core` | Harness 核心方法论骨架（栈无关）：10 阶段 K 流程 + 元流程 M0–M5、5 角色 agent、流程层 skill、旁路组件（codegraph / wiki-engine）。 |
| `harness-profile-python` | Python 栈 profile：FastAPI/pytest/ruff 编码·评审·测试 skill + 栈绑定层。依赖 `harness-core`。 |
| `harness-profile-react-vite` | React+Vite+TypeScript FE 栈 profile：FE 编码·评审·测试 skill 套件 + 栈绑定层。依赖 `harness-core`。 |

栈 profile 按需安装，例如：

```
/plugin install harness-profile-python@cc-harness-works
```
```
/plugin install harness-profile-react-vite@cc-harness-works
```

## 首次使用 · 建完就核验

安装 + 首次会话后，harness 会自动落骨架并尝试建 CodeGraph 索引 / wiki 骨架。但**骨架建好 ≠ 能查询**，装完请主动核验一次：

```
cg doctor       # 看引擎运行时（runtime）是否就绪
cg status       # 看索引（index）与 pendingChanges
ls wiki/        # 看 wiki 是否已摄取内容（只有骨架时基本为空）
```

### 坑① · CodeGraph 索引已建但缺运行时

`cg doctor` 显示 `index: initialized` 但 `runtime: NONE` → 引擎运行时没装成 / 丢失。此时 `cg` 查询返回退出码 10（RUNTIME_MISSING），会降级回退 grep——不阻断会话，但查不到符号级结果。

补救：重跑一键就绪命令（全步骤幂等，可反复补装）：

```
/harness-core:bootstrap
```

### 坑② · wiki 只有骨架无内容

bootstrap 只落 wiki **骨架**，不做内容摄取。摄取需先注入 API key（走环境变量，**切勿写入任何文件 / 提交入库**）：

```
export DEEPSEEK_API_KEY=...   # 仅环境变量，勿落盘
```

然后按 `wiki-engine` SKILL.md 的批循环工作流增量摄取。

### 坑③ · 第二个项目没自动 bootstrap

自动 bootstrap 语义是「**仅第一次 · 每项目一次**」——每个项目各自独立触发。若想关闭自动行为，任选其一：

```
export HARNESS_AUTO_BOOTSTRAP=0        # 环境变量逃生阀
# 或在 HARNESS_CONFIG.yaml 写：
#   bootstrap.auto: false
```

需要手动补跑时随时执行 `/harness-core:bootstrap`（幂等）。

> 说明：v0.6.1 起，bootstrap 状态哨兵已按项目隔离（落项目内 `.harness/state/`），修复了旧版「同机全部项目只自动 bootstrap 一次」的问题。

### 存量升级：一次性重 bootstrap（预期，无害）

从旧版（哨兵落全局）升级的项目，因哨兵落点改为项目本地，**首次会话可能重跑一次 bootstrap**。这是一次性迁移副作用，幂等无害（已装好的引擎 / 索引 / wiki 骨架各步骤会自动跳过）。

## 插件升级后 · 脚手架怎么更新

升级插件后（`/plugin marketplace update cc-harness-works` + `/reload-plugins`），**大部分脚手架会自动更新**：hooks / commands / workflows / skills / agents / rules 在下个会话由 drift-sync 从新版插件缓存**单向刷新**（你本地改过的镜像文件会被识别为定制、告警跳过、**绝不覆盖你的改动**）。所以规则 / 流程 / 工作流类的修复，升级 + 重载后即自动生效，无需手工干预。

> ⚠️ **重点：引擎组件不随插件升级自动刷新，需手动重跑 bootstrap。**
> `.harness/components/`（codegraph / wiki-engine 的二进制 + 注册脚本）只在**首次** bootstrap 落盘；成功哨兵 `.bootstrap_done` 无版本戳，不会随插件升级自动重跑。**若某次发版更新了引擎组件，请手动执行一次**（全步骤幂等，已就绪的步骤自动跳过）：
>
> ```
> /harness-core:bootstrap
> ```

此外 `_TEMPLATE`（变更卡模板）为 no-clobber——存在即不覆盖。发版若改了模板结构，需手动删除 `.harness/changes/_TEMPLATE`，下个会话会自动从新版补齐。

## 随项目分发插件声明 · /harness-core:pin-to-project

装好插件后，如果你是项目主人、希望**队友克隆仓库即被提示装好同一套插件**（免去每人手工 `/plugin marketplace add` + `/plugin install`），可主动运行：

```
/harness-core:pin-to-project
```

它会把 marketplace（`cc-harness-works`）+ 本项目**已启用插件**的声明 JSON-safe 合并写进 tracked 的 `.claude/settings.json`（保留 `statusLine` 等既有键）。提交入库后，队友克隆并信任仓库时，Claude Code 会提示安装这些插件。

- **opt-in 语义**：仅在你**主动运行**本命令时才写，绝不自动触发、不注册任何 hook。写完记得 `git add .claude/settings.json && git commit` 才会随仓库分发。
- **供应链知情提示**：把该声明写入 tracked 配置并入库 = 任何**克隆并信任本仓库**的人会被 Claude Code 提示安装此 marketplace + 插件——这是你作为项目主人**主动的分发决定**，会影响所有队友，请先 review diff 再提交。
- **版本局限**：声明**只锁「启用哪些插件」，不锁 sha/版本**；克隆者安装的是 marketplace **当前 HEAD 版本**，可能与你本地版本不同。

## 完整指南

分发渠道、双仓同步、认证排障等完整说明见 [plugin-distribution-guide](docs/guides/plugin-distribution-guide.md)。
EOF
}

if [ -n "$PRINT_GENERATED" ]; then
  case "$PRINT_GENERATED" in
    README.md) print_public_readme; exit 0 ;;
    *) echo "ERROR: 不支持的 generated destination：$PRINT_GENERATED" >&2; exit 2 ;;
  esac
fi

# ---------- 定位私有仓根（用脚本自身路径推导 · 不依赖调用者 cwd）----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"   # .harness/scripts/ → 上跳两级 = 仓库根
MANIFEST="$REPO_ROOT/.harness/config/public_distribution_manifest.json"

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 不可用，无法解析公共分发 manifest" >&2; exit 1; }
# 必须是与源仓无祖先/后代关系的非根目录；此检查在任何 target mkdir/rm 之前完成。
TARGET="$(python3 - "$TARGET_INPUT" "$REPO_ROOT" <<'PY'
from pathlib import Path
import os
import sys

target_input = Path(sys.argv[1]).expanduser()
if not target_input.is_absolute():
    target_input = Path.cwd() / target_input
# Inspect the caller-provided path before resolve(), otherwise a symlink root is
# silently hidden by normalization.
current = Path(target_input.anchor)
for part in target_input.parts[1:]:
    current = current / part
    if current.is_symlink():
        raise SystemExit(f"ERROR: target path contains an existing symlink component: {current}")
target = Path(os.path.abspath(target_input))
repo = Path(sys.argv[2]).resolve()
resolved_target = target.resolve(strict=False)
if resolved_target == Path(resolved_target.anchor) or resolved_target == repo or resolved_target in repo.parents or repo in resolved_target.parents:
    raise SystemExit(f"ERROR: target 不得是文件系统根、源仓、源仓祖先或源仓子目录：{resolved_target}")
print(target)
PY
)" || exit 1

[ -f "$MANIFEST" ] || { echo "ERROR: 公共分发 manifest 缺失 $MANIFEST" >&2; exit 1; }

MANIFEST_OUTPUT="$(python3 - "$MANIFEST" <<'PY'
import json
from pathlib import Path, PurePosixPath
import sys

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"ERROR: 无法解析公共分发 manifest {path}: {exc}")
if data.get("schema_version") != 1 or not isinstance(data.get("entries"), list):
    raise SystemExit("ERROR: 公共分发 manifest 必须是 schema_version=1 且 entries 为数组")
destinations = []
for index, entry in enumerate(data["entries"]):
    if not isinstance(entry, dict) or entry.get("type") not in {"file", "directory", "generated"}:
        raise SystemExit(f"ERROR: manifest entries[{index}] 类型非法")
    values = [entry.get("type", ""), entry.get("source", ""), entry.get("destination", "")]
    for value in values[1:]:
        if value:
            parsed = PurePosixPath(value)
            if parsed.is_absolute() or ".." in parsed.parts or any(ch in value for ch in "|\t\n"):
                raise SystemExit(f"ERROR: manifest entries[{index}] 路径不安全: {value!r}")
    if not values[2]:
        raise SystemExit(f"ERROR: manifest entries[{index}] 缺 destination")
    destination = PurePosixPath(values[2])
    conflict = next(
        (
            existing
            for existing in destinations
            if destination == existing
            or existing in destination.parents
            or destination in existing.parents
        ),
        None,
    )
    if conflict is not None:
        raise SystemExit(
            "ERROR: conflicting manifest destinations "
            f"(duplicate or ancestor/descendant): {conflict} <-> {destination}"
        )
    destinations.append(destination)
    print("|".join(values))
PY
)" || exit 1
mapfile -t MANIFEST_ROWS <<< "$MANIFEST_OUTPUT"
[ "${#MANIFEST_ROWS[@]}" -gt 0 ] || { echo "ERROR: 公共分发 manifest 无条目" >&2; exit 1; }

echo "▶ 私有仓根 REPO_ROOT = $REPO_ROOT"
echo "▶ 公有仓工作副本 TARGET = $TARGET"
echo "▶ 公共分发 manifest = $MANIFEST"

# ---------- 源存在性校验（manifest 中复制源须齐全）----------
for row in "${MANIFEST_ROWS[@]}"; do
  IFS='|' read -r entry_type source destination <<< "$row"
  case "$entry_type" in
    file)      [ -f "$REPO_ROOT/$source" ] || { echo "ERROR: manifest 文件源缺失 $source" >&2; exit 1; } ;;
    directory) [ -d "$REPO_ROOT/$source" ] || { echo "ERROR: manifest 目录源缺失 $source" >&2; exit 1; } ;;
    generated) : ;;
  esac
done

# ---------- target 写删安全预检（任何 mkdir/rm/cp 前）----------
# 拒绝 target 根、destination 顶层或嵌套路径中任何既有 symlink，并验证
# strict=False 解析结果仍位于 target。该预检在单进程正常边界 fail-closed；
# 后续 rm 使用 find -P，避免排除阶段跟随目录 symlink。
python3 - "$TARGET" "${MANIFEST_ROWS[@]}" <<'PY'
from pathlib import Path, PurePosixPath
import sys

target = Path(sys.argv[1])
if target.is_symlink():
    raise SystemExit(f"ERROR: target root must not be a symlink: {target}")
resolved_target = target.resolve(strict=False)
for row in sys.argv[2:]:
    _entry_type, _source, destination_value = row.split("|", 2)
    destination = PurePosixPath(destination_value)
    current = target
    for part in destination.parts:
        current = current / part
        if current.is_symlink():
            raise SystemExit(
                f"ERROR: target destination contains an existing symlink component: {current}"
            )
    resolved_destination = (target / Path(*destination.parts)).resolve(strict=False)
    try:
        resolved_destination.relative_to(resolved_target)
    except ValueError as exc:
        raise SystemExit(
            f"ERROR: target destination resolves outside target: {destination} -> {resolved_destination}"
        ) from exc
PY

# ---------- 幂等: 先清理 manifest 管理的 target 目标 ----------
echo "▶ 清理 target 内 manifest 管理的目标（幂等前置）..."
mkdir -p "$TARGET"
for row in "${MANIFEST_ROWS[@]}"; do
  IFS='|' read -r entry_type source destination <<< "$row"
  rm -rf -- "$TARGET/$destination"
done

# ---------- 按 manifest 复制文件与目录；generated 条目由下方具名生成器处理 ----------
echo "▶ 按公共分发 manifest 复制文件与目录..."
for row in "${MANIFEST_ROWS[@]}"; do
  IFS='|' read -r entry_type source destination <<< "$row"
  case "$entry_type" in
    file)
      mkdir -p "$(dirname "$TARGET/$destination")"
      cp -p -- "$REPO_ROOT/$source" "$TARGET/$destination"
      ;;
    directory)
      mkdir -p "$(dirname "$TARGET/$destination")"
      cp -Rp -- "$REPO_ROOT/$source" "$TARGET/$destination"
      ;;
    generated) : ;;
  esac
done

# ---------- 组装后剔除 manifest 声明的目录名 / 文件 glob ----------
echo "▶ 应用 manifest 的目录与文件排除策略..."
while IFS=$'\t' read -r exclusion_kind exclusion_value; do
  case "$exclusion_kind" in
    name)
      find -P "$TARGET" -type d -name "$exclusion_value" -prune -exec rm -rf -- {} +
      ;;
    glob)
      # *.env 不匹配 *.env.example；其余 glob 同样仅作用于文件 basename。
      find -P "$TARGET" -type f -name "$exclusion_value" -delete
      ;;
  esac
done < <(python3 - "$MANIFEST" <<'PY'
import json
from pathlib import Path
import sys

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
exclusions = data.get("directory_exclusions", {})
for value in exclusions.get("names", []):
    if not isinstance(value, str) or not value or "/" in value or "\t" in value or "\n" in value:
        raise SystemExit(f"ERROR: 非法排除目录名: {value!r}")
    print(f"name\t{value}")
for value in exclusions.get("file_globs", []):
    if not isinstance(value, str) or not value or "/" in value or "\t" in value or "\n" in value:
        raise SystemExit(f"ERROR: 非法排除文件 glob: {value!r}")
    print(f"glob\t{value}")
PY
)

# ---------- 生成对外 README.md（同一函数供纯输出与落盘使用）----------
echo "▶ 生成对外 README.md（面向安装者）..."
print_public_readme > "$TARGET/README.md"
chmod 0644 "$TARGET/README.md"

echo "✅ 组装完成 → $TARGET"

# ---------- 结尾: 打印后续人工命令提示（仅提示 · 绝不执行）----------
cat <<EOF

────────────────────────────────────────────────────────────
后续人工命令提示（本脚本不执行任何 git / gh 动作）：

  # 首次发布前（仅一次）创建公有仓：
  gh repo create yanaoyong/cc-harness-works --public

  # 推送组装结果：
  cd "$TARGET" && git add -A && git commit -m "sync: 更新可分发子集" && git push

  ⚠ push 前请对完整可分发子集跑敏感信息扫描（AC-7 push 硬前置门），clean 方可 push。
────────────────────────────────────────────────────────────
EOF
