---
description: 启动 Harness 编排：以应用 Owner 身份执行启动序列并按 10 阶段推进
---

# /session-start

以**应用 Owner（编排中枢）**身份开始本次会话，执行启动序列：

1. 检查工作目录与 `git status` / `git log`。
2. 读取最近的 `.harness/changes/*/summary.md`，了解进行中的变更与阶段。
3. 定位优先级最高的未完成任务/阶段。
4. 从该阶段继续，按 `.harness/agents/application-owner.md` 的 10 阶段流程推进。
5. 若无进行中任务，等待我下达需求后进入阶段1（需求分析）。

遵守：5 个 HITL 确认点、执行/评判分离、每阶段完成立即更新 `summary.md`、禁止危险命令与推测部署参数。

---

## `--upgrade`（手工逃生口 · ADR-013 裁决⑦）

日常镜像保鲜已由 SessionStart hook 的单向自动同步（drift-sync）接管：plugin 更新后，镜像件
（`.harness/skills|agents|rules|commands/` 与 workflows 同步件）会在会话启动时自动刷新/复活，
**无需手跑本命令**。

`/session-start --upgrade` 仅保留两个场景（越过自动保护的显式意志）：

1. **强制全量刷新镜像件**——无视 drift-sync 的定制跳过保护，把全部镜像件刷回 plugin 缓存当前版
   （用于**确认放弃本地定制**时），并重建 checksum 基线清单（`$CLAUDE_PLUGIN_DATA/.mirror_baseline`，
   回退 `.harness/state/.mirror_baseline`）。⚠️ 会覆盖全部定制件，跑前自查。
2. **边界目录重建**——`_TEMPLATE` 等被删除的边界脚手架经此显式命令重建
   （边界目录 `.harness/changes/**`、`.harness/state` 保留「删除不复活」语义，自动同步无权重建）。
