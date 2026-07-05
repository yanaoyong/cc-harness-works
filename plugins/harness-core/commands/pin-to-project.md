---
description: opt-in · 把 marketplace（cc-harness-works）+ 本项目已启用插件声明 JSON-safe 合并写进 tracked .claude/settings.json，随 git 分发给队友（免手工 add+install）
---

# /pin-to-project

**opt-in 分发入口**：项目主人主动运行，把 marketplace + 本项目已启用插件声明写进消费项目 **tracked** 的 `.claude/settings.json`，随 git 提交分发给克隆仓库的队友——队友克隆并信任仓库后，Claude Code 会提示他们安装此 marketplace + 插件，免去手工 `/plugin marketplace add` + `/plugin install`。

**全部实现逻辑在共享脚本 `harness_pin_to_project.sh` 内**（单一实现）；本 command 只负责：定位脚本 → dry-run 展示 → 供应链知情提示 → 确认后执行 → 转述结果。**禁止在本流程中内联复刻脚本的合并/匹配逻辑。禁止注册任何 hook**（本命令是主动入口，不自动触发）。

按以下步骤执行：

## ① 定位实现脚本（三级 · 全不命中不得静默）

```bash
SCRIPT=""
if [ -n "${CLAUDE_PLUGIN_ROOT}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/harness_pin_to_project.sh" ]; then
  SCRIPT="${CLAUDE_PLUGIN_ROOT}/hooks/harness_pin_to_project.sh"          # 第一定位：plugin 安装态（消费方无 plugins/ 目录，必须经此变量）
else
  TOP="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  [ -f "$TOP/plugins/harness-core/hooks/harness_pin_to_project.sh" ] && \
    SCRIPT="$TOP/plugins/harness-core/hooks/harness_pin_to_project.sh"    # 回退：本仓开发态
fi
echo "SCRIPT=${SCRIPT:-NOT_FOUND}"
```

- `SCRIPT` 为空 → **兜底提示并终止**（不静默）：告知我「未找到 `harness_pin_to_project.sh`——plugin 安装可能异常（`CLAUDE_PLUGIN_ROOT` 未指向有效 harness-core 安装，且本仓开发态路径也不存在）；请检查 plugin 安装或重装 harness-core」。不要尝试用其他方式替代执行。

## ② dry-run 展示将写入的声明（零写入 · 不落盘）

```bash
bash "$SCRIPT" --dry-run
```

- stdout 打印将合并进 `.claude/settings.json` 的 JSON 声明（`extraKnownMarketplaces.cc-harness-works` + 若有匹配则 `enabledPlugins`）；stderr（前缀 `[harness:pin-to-project]`）会提示匹配到的键或「零匹配」。
- 把 dry-run 输出**原样转述给我**，明确列出：将写入哪个 marketplace、将启用哪些插件键（或零匹配时仅写 marketplace 声明）。

## ③ 供应链知情提示（写入前必须告知 · 不得跳过）

在执行落盘前，**明确告诉我**：

> 把该声明写入 tracked `.claude/settings.json` 并提交入库 = 任何**克隆并信任本仓库**的人，其 Claude Code 会提示安装此 marketplace（`cc-harness-works`）+ 上述已启用插件。这是你作为**项目主人主动的分发决定**，会影响所有队友。此外声明**只锁启用、不锁 sha/版本**（R-1）——克隆者装的是 marketplace 当前 HEAD 版本。

然后**明确询问我是否执行落盘，等待确认**。我未确认前不得进入步骤 ④。

## ④ 确认后执行落盘

```bash
bash "$SCRIPT"
```

- JSON-safe 合并写入：保留 `statusLine` 等所有既有键；非法 JSON 目标会被拒绝触碰并留痕；无 python3 时仅在文件不存在时写全新最小文件、已存在则放弃并留痕（不冒险破坏 JSON）。
- 写入前脚本会在 stderr 再打一句供应链风险提示（与步骤 ③ 同义，运行时留痕）。

## ⑤ 转述结果与退出码

把 stdout/stderr 结果转述给我，并按退出码补充解读：

| 退出码 | 含义 | 向我提示 |
|---|---|---|
| 0 | 成功写入（或 dry-run 展示完成） | 声明已合并进 `.claude/settings.json`；记得 `git add .claude/settings.json && git commit` 才会随仓库分发给队友 |
| 2 | 非 git 仓库 / 用法错误 | 确认当前目录在目标项目 git 仓库根内后重跑 |
| 3 | installed_plugins.json 缺失 / 非法 / 顶层非 dict（R-4） | 本项目可能尚未安装任何插件，或 `installed_plugins.json` 损坏；脚本拒绝臆造 enabledPlugins；先确认插件已安装再重跑 |
| 4 | 无 python3 且 settings.json 已存在 → 放弃合并 | 环境缺 python3，为不破坏既有 JSON 已放弃；请安装 python3 后重跑，或人工把声明合并进去 |
| 6 | 目标 settings.json 非法 JSON / 非对象 → 拒绝触碰 | 人工检查并修复 `.claude/settings.json` 后重跑 |
| 7 | 原子写盘失败 | 检查目录权限/磁盘后重跑；文件未被破坏 |

> 提示：脚本不写任何 key/token；API key 一律走环境变量、不入库。写入后请人工 review `.claude/settings.json` 的 diff 再提交。
