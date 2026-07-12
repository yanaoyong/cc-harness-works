---
name: setup
trigger: 用户显式调用 `/setup`（hook 被禁用时的降级回退）
inputs: 无
outputs: 常驻契约注入内容展示 + 脚手架位置提示
version: 1.2.0
updated: 2026-07-12
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
---

# Skill · setup（常驻契约注入降级路径）

## 1. 目的

作为 SessionStart hook 被禁用时的**显式降级回退路径**，手动注入完整调度契约（**cat 权威源全文** · 与 hook 注入内容完全相同、零双源）。

> **机制演进（chore-l1-slim-and-tier-v3-20260712 · ADR-018）**：本 skill 曾读取一份**精简注入副本**（原 `skills/setup/` 下的精简子集）展示；该副本是 P1 双源漂移温床，已随 ADR-018 **彻底退役**（删除 · git 历史留档）。降级注入改为**直接 cat 四个权威源文件全文**（`application-owner.md` + rules 三件套），与 `session_start_resident_contract.sh` 主注入**同源、逐字节等价**，从根上消除双源。

## 2. 触发条件

用户显式调用 `/setup`，通常在以下场景：
- SessionStart hook 被禁用或未生效
- 需要手动重新加载常驻契约（参考层 / 完整调度契约）
- 首次安装 plugin 后的 setup 步骤

## 3. 功能

1. **注入常驻契约**：按 UQ-9 序 **cat 四个权威源文件全文**并展示（见 §4）——`agents/application-owner.md` → `rules/工程结构.md` → `rules/开发流程规范.md` → `rules/项目编码规范.md`，段间加来源标头，首行背书声明 `[harness:resident_contract]`。
2. **提示脚手架位置**：引导用户找到 `_TEMPLATE` 等脚手架资源（见 §7）。

## 3.5 硬守卫 · CLAUDE.md @import 常驻检测（注入前必须执行 · 不是可选提示）

> 来源：feat-claudemd-full-restore-20260706（AC-3c）；语义随 ADR-018 更新为**过渡期兼容**——与 SessionStart hook 守卫①.5 同款双串检测，防存量旧版 CLAUDE.md（仍含 @import）双份加载。

**执行注入（§3 功能1）之前，必须先检查仓库根 `CLAUDE.md` 是否仍含 application-owner.md 的 @import**（双串枚举，`grep -F` 字面匹配）：

```bash
TOP="$(git rev-parse --show-toplevel)"
grep -F '@.harness/agents/application-owner.md' "$TOP/CLAUDE.md" 2>/dev/null
grep -F '@plugins/harness-core/agents/application-owner.md' "$TOP/CLAUDE.md" 2>/dev/null
```

- **任一串命中**（存量旧版 CLAUDE.md · 过渡期）→ **不注入**（契约已随 @import 常驻，注入即双份加载），提示用户："CLAUDE.md 仍含 @import 常驻串（过渡期），契约已加载，注入冗余，已跳过。迁移=删旧 CLAUDE.md，由 session-start.sh 复原最小新版后由 SessionStart hook 接管注入"。脚手架落盘检查（§7 功能2）照常执行。
- **两串均不命中**（最小新版 CLAUDE.md 无 @import，含 CLAUDE.md 不存在）→ 照常按 §4 手动 cat 权威源全文注入。

本守卫为**硬守卫**：命中即不注入，不得以"用户显式调用了 /setup"为由绕过。

## 4. 使用方法

```
/setup
```

调用后，本 skill 会：
- **先执行 §3.5 硬守卫检测**（命中 @import 则不注入）
- 按 UQ-9 序 **cat 四个权威源文件全文**（三级回退链定位 base · 见 §6），段间加来源标头
- 将完整内容展示给你（约 ~50–78KB · 与 hook 注入等价）
- 提示：常驻契约已手动注入，可继续工作

## 5. 与 SessionStart hook 的关系

- **SessionStart hook 为主路径**：每 session 自动注入（零 friction · `session_start_resident_contract.sh`）
- **setup skill 为降级路径**：hook 未启用或失效时手动调用
- **机制对齐**：两者注入的内容**完全相同**——都是 **cat 同一批权威源文件全文**（`application-owner.md` + rules 三件套），无中间摘要副本、零双源漂移

与 CLAUDE.md「常驻契约注入（SessionStart 背书条款）· hook 失效降级路径」一致——hook 不可用则人工显式触发 `/setup`。

## 6. 注入内容与三级回退链

以下是完整调度契约的注入源（**按 UQ-9 序 cat 全文**）；base 目录经三级回退链定位——首个"四文件全可读"的 base 即用：

- 链①：`$TOP/.harness/`（消费方安装态镜像 / 本仓落盘镜像）
- 链②：`$TOP/plugins/harness-core/`（本仓开发态权威源）
- 链③：`$CLAUDE_PLUGIN_ROOT/`（plugin 包内直读 · 兜首会话空窗；`CLAUDE_PLUGIN_ROOT` 空则跳过本级防假路径）

四个权威源文件（相对 base · UQ-9 拼接序）：

1. `agents/application-owner.md`（编排中枢 · 10 阶段 + 元流程调度 + 模型档 + 委派适配子条款）
2. `rules/工程结构.md`（分层与目录约束）
3. `rules/开发流程规范.md`（10 阶段流程纪律）
4. `rules/项目编码规范.md`（编码硬约束）

<!-- 动态内容开始：实际调用时 cat 上述四文件 -->

**注意**：在实际使用时，本 skill 会按三级回退链定位 base，然后 `cat` 上述四个权威源文件全文（段间加 `─── 以下源自 <path> ───` 标头）并展示。若你看到此消息，说明正在阅读 skill 定义本身；实际调用 `/setup` 时会看到完整的常驻契约全文。

<!-- 动态内容结束 -->

## 7. 脚手架落盘（RM-2026-141）

若 SessionStart hook 被禁用或未生效，可手动触发脚手架落盘。

### 用法

```
/setup
```

调用 `/setup` 时会自动：
1. 注入常驻契约（功能1，见 §4）
2. 检查并落盘 _TEMPLATE 脚手架（功能2，本节）

### 行为

- **检查**：项目 `.harness/changes/_TEMPLATE` 是否存在
- **不存在**：从 plugin 复制到项目，给出成功提示
- **已存在**：跳过，提示 "_TEMPLATE 脚手架已存在"
- **失败**：给出诊断信息（权限/磁盘空间/plugin 结构异常）

### 注意

- 手动落盘**不覆盖**已有 _TEMPLATE（尊重用户修改 · 非破坏性 AC-d）
- 建议首次使用 plugin 后调用一次 `/setup` 确保脚手架就位
- 正常情况下 SessionStart hook 会自动落盘，无需手动操作

### 脚手架资源位置

**变更卡模板**（主要）：
- Plugin 源：`${CLAUDE_PLUGIN_ROOT}/.harness/changes/_TEMPLATE/`
- 项目落盘：`${PROJECT_ROOT}/.harness/changes/_TEMPLATE/`
- 用途：新建变更卡时复制此模板（`cp -r .harness/changes/_TEMPLATE ...`）

**其他脚手架**：
- 文档模板：`docs/` 下各模板文件
- skill 模板：`.harness/skills/_TEMPLATE/`

## 8. 故障排除

**Q: 调用 `/setup` 后看不到常驻契约内容？**  
A: 检查三级回退链 base 是否有四个权威源文件（`agents/application-owner.md` + `rules/工程结构.md` / `开发流程规范.md` / `项目编码规范.md`）可读；四文件不全可读则跳过注入。

**Q: SessionStart hook 和 setup skill 哪个优先？**  
A: SessionStart hook 为主路径（自动）；setup skill 为降级路径（手动）。推荐依赖 hook，仅在 hook 失效时手动调用 skill。

**Q: 两者注入的内容是否一致？**  
A: 完全一致——都是 cat 同一批权威源文件全文（`application-owner.md` + rules 三件套），无中间摘要副本，从根上无双源漂移（ADR-018 退役精简副本后）。
