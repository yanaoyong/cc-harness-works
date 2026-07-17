---
description: opt-in 启用会话 transcript 归档：定位启用脚本 → 校验用户提供的 GitHub 私有归档仓（fail-closed）→ 写 config.json → 转述后续 opt-in 步骤
---

# /transcript-archive-enable

**薄入口**：完整引导逻辑在 `skills/transcript-archive/SKILL.md`（启用引导）+ `skills/transcript-archive/scripts/enable_archive.sh`（fail-closed 校验脚本）。本 command 只负责定位脚本 → 取用户提供的私有归档仓 URL → 运行校验 → 转述结论。**禁止在本流程内联复刻脚本的校验 / 落盘逻辑。**

## ① 取归档仓 remote URL（必填 · 无缺省 · 不默推）

要求用户提供一个 **GitHub 私有归档仓** remote URL（`https://github.com/<o>/<r>.git` 或 `git@github.com:<o>/<r>.git`）。**未提供则停下询问**，不得臆测 / 不得硬编码任何用户级取值。归档含会话原始记录——必须是**私有**专仓，非业务仓 / 非公有分发仓。

## ② 定位启用脚本（三级 · 全不命中不得静默）

```bash
SCRIPT=""
if [ -n "${CLAUDE_PLUGIN_ROOT}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/transcript-archive/scripts/enable_archive.sh" ]; then
  SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/transcript-archive/scripts/enable_archive.sh"   # plugin 安装态
else
  TOP="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  [ -f "$TOP/plugins/harness-core/skills/transcript-archive/scripts/enable_archive.sh" ] && \
    SCRIPT="$TOP/plugins/harness-core/skills/transcript-archive/scripts/enable_archive.sh"  # 本仓开发态
fi
echo "SCRIPT=${SCRIPT:-NOT_FOUND}"
```

- `SCRIPT` 为空 → **兜底提示并终止**：告知用户「未找到 `enable_archive.sh`——plugin 安装可能异常；请检查 harness-core 安装」。不要用其它方式替代执行。

## ③ 运行校验脚本（把 URL 作 argv 传入 · 禁 eval 拼接）

```bash
bash "$SCRIPT" "<用户提供的私有归档仓 URL>"
```

- 脚本执行 fail-closed 校验链：**gh 缺失（exit 3）/ owner-repo 解析失败（exit 4）/ visibility 查不到（exit 5）/ 非 private（exit 6）/ archive_dir 非空非 git（exit 7）/ clone 失败（exit 8）** 任一即拒绝启用、不写 config。
- 校验全过（exit 0）→ 写 `<STATE_HOME>/config.json`（`enabled:true` + 冻结键缺省；已有 config 合并保留用户自定键值）。`STATE_HOME` = `${HARNESS_TRANSCRIPT_ARCHIVE_HOME:-~/.claude/harness-transcript-archive}`。

## ④ 转述结论与后续 opt-in 步骤

- 把脚本 stderr 的每步结论 + 退出码含义原样转述给用户。
- 失败 → 按退出码给修复建议（见 SKILL.md §6 故障排除），不改脚本、不绕过 fail-closed。
- 成功 → 提示后续**均为手动 opt-in**步骤，转述 SKILL.md §4 要点：存量止血备份（一次性，不自动化）/ `cleanupPeriodDays` 建议放宽（仅提示、不替改）/ SessionEnd hook 注册片段 / cron 样例 / denylist / `cold_sync_cmd`（非本机去向，不受控介质自套 age·gpg）/ 保留策略配置键。

> 未启用 = 提取器 / hook / cron 一切零副作用（AC-5）。本命令是启用的唯一显式入口之一（另一为直接调 `transcript-archive` skill）。
