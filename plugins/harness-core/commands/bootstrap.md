---
description: 一键就绪 Harness 组件运行时：探测并展示动作 → 用户确认 → 同步执行 bootstrap 六步（组件落盘/装引擎/cg init/wiki 骨架/skill 注册/就绪报告）
---

# /bootstrap

引导式一键入口（方案 A）。**全部实现逻辑在共享脚本 `harness_bootstrap.sh` 内**（A/B 单一实现，AC-5）；本 command 只负责：定位脚本 → 探测并向我展示将执行的动作 → 经我确认后以 `--yes` 同步执行 → 转述就绪报告。**禁止在本流程中内联复刻脚本的任何安装/落盘逻辑。**

按以下步骤执行：

## ① 定位实现脚本（三级 · 全不命中不得静默）

```bash
SCRIPT=""
if [ -n "${CLAUDE_PLUGIN_ROOT}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/harness_bootstrap.sh" ]; then
  SCRIPT="${CLAUDE_PLUGIN_ROOT}/hooks/harness_bootstrap.sh"          # 第一定位：plugin 安装态（消费方无 plugins/ 目录，必须经此变量）
else
  TOP="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  [ -f "$TOP/plugins/harness-core/hooks/harness_bootstrap.sh" ] && \
    SCRIPT="$TOP/plugins/harness-core/hooks/harness_bootstrap.sh"    # 回退：本仓开发态
fi
echo "SCRIPT=${SCRIPT:-NOT_FOUND}"
```

- `SCRIPT` 为空 → **兜底提示并终止**（不静默）：告知我「未找到 `harness_bootstrap.sh`——plugin 安装可能异常（`CLAUDE_PLUGIN_ROOT` 未指向有效 harness-core 安装，且本仓开发态路径也不存在）；请检查 plugin 安装或重装 harness-core」。不要尝试用其他方式替代执行。
- 若 `${CLAUDE_PLUGIN_DATA:-$TOP/.harness/state}/.bootstrap_running` 存在 → **先读其首行 pid 并以 `kill -0 <pid>` 判存活**（与 session-start.sh / hint hook 同口径）：
  - **pid 存活** → 后台 bootstrap（B 路径）正在执行，先告知我并建议等待其完成（日志：同目录 `bootstrap.log`），不要并行重跑；
  - **pid 已死** → 属残留哨兵（后台任务曾被强杀/重启中断，收尾清理未执行），告知我后**可直接继续本流程重跑**（脚本全幂等；session-start 挂载下会话也会自动清除该残留），不要被残留哨兵引导停下等待。

## ② 零写入探测（`--report-only`）

```bash
bash "$SCRIPT" --report-only
```

stdout 固定三行机读格式：`engine=ready|missing` / `index=ready|missing` / `wiki=ready|missing`（exit 0 = 三全，exit 20 = 有缺项）。

- **三项全 ready（exit 0）** → 直接告知我「已全就绪，无需 bootstrap」，结束（可顺带跑一次 `--report-only` 之外的 `cg doctor` 佐证，不强制）。
- **有缺项（exit 20）** → 进入步骤 ③。

## ③ 安装前展示将执行的动作（等待我确认 · 不得跳过）

基于缺项清单，向我完整展示本次将执行的动作，**至少包含**：

1. **组件持久落盘**：`components/{codegraph,wiki-engine}` → `$TOP/.harness/components/`（后续 skill 注册/符号链接一律指向该仓库内持久落点，非版本化 plugin 缓存）。
2. **引擎安装**（仅 `engine=missing` 时）：
   - 下载 URL：`HARNESS_CODEGRAPH_INSTALL_URL` 已设则展示其值，否则从 `$SCRIPT` 头部常量区读取内置默认值展示（只读取展示，不复刻逻辑）；
   - sha256 pin：`HARNESS_BOOTSTRAP_SHA256` 已设则展示其值，否则展示脚本内置 pin（若为占位值 `PIN-PENDING-REFRESH-AT-PLUGIN-RELEASE`，**提前告知我脚本将拒装 exit 21**，需先提供 `HARNESS_BOOTSTRAP_SHA256` 或等 plugin 发版刷新 pin）；
   - 校验纪律：sha256 不匹配 / pin 非法 / 无校验工具 → fail-closed 拒装；
   - 引擎落盘位置：上游 install.sh 已知位置（`$HOME/.codegraph/bin`、`$HOME/.local/bin` 等，脚本内绝对路径探测后注入本进程 PATH）。
3. **`cg init` 建索引** → `$TOP/.codegraph/`（仅 `index=missing` 时）。
4. **wiki 骨架落盘** → `$TOP/wiki/`（只落骨架不摄取；摄取待 `DEEPSEEK_API_KEY` 注入后随卡增量进行）。
5. **skill 注册** → `.claude/skills/{codegraph,wiki-engine}`，注入路径指向 `.harness/components/`。

然后**明确询问我是否执行，等待确认**。我未确认前不得进入步骤 ④。

## ④ 确认后同步执行

```bash
bash "$SCRIPT" --yes
```

- 同步前台执行（A 路径不受 hook 时限约束；**不要加 `--background`**）；引擎下载可能耗时数分钟属正常。
- 进度/警告在 stderr（前缀 `[harness:bootstrap]`），就绪报告在 stdout。

## ⑤ 转述就绪报告与退出码

把 stdout 就绪报告（引擎/索引/wiki 各项 ✅/⚠️ + 后续步骤提示）原样转述给我，并按退出码补充解读：

| 退出码 | 含义 | 向我提示 |
|---|---|---|
| 0 | 全就绪（`.bootstrap_done` 已落） | 无需动作；如需摄取 wiki，export `DEEPSEEK_API_KEY` 后随卡增量进行 |
| 20 | 部分完成（有步骤跳过/失败，已尽力推进） | 转述 stderr warning 与 `$STATE_DIR/.bootstrap_failed` 内容；脚本全幂等，排除原因后可直接重跑本命令 |
| 21 | sha256 校验失败 / pin 占位 / 无校验工具 → 拒装 | 提示：pin 需刷新（plugin 发版纪律）或上游 install.sh 已变更；可核实后以 `HARNESS_BOOTSTRAP_SHA256` 显式覆盖重跑 |
| 22 | 无网络 / 无 curl / 下载失败或超时 | 提示检查网络代理/出站策略；离线环境可用 `HARNESS_CODEGRAPH_INSTALL_URL` 指向本地镜像，或跳过引擎安装仅完成其余各步 |
| 2 | 用法错误 / 非 git 仓库 | 确认当前目录在目标项目 git 仓库内后重跑 |

诊断哨兵位置：`$STATE_DIR` = `${CLAUDE_PLUGIN_DATA:-$TOP/.harness/state}`（`.bootstrap_done` / `.bootstrap_failed` / `bootstrap.log`）。
