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

分发渠道、双仓同步、认证排障等完整说明见项目分发指南（plugin-distribution-guide）。
