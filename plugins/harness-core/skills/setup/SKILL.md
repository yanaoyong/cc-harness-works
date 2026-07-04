---
name: setup
trigger: 用户显式调用 `/setup`（hook 被禁用时的降级回退）
inputs: 无
outputs: 常驻契约注入内容展示 + 脚手架位置提示
version: 1.0.0
updated: 2026-06-28
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
---

# Skill · setup（常驻契约注入降级路径）

## 1. 目的

作为 SessionStart hook 被禁用时的**显式降级回退路径**，手动注入常驻契约可重建子集。

## 2. 触发条件

用户显式调用 `/setup`，通常在以下场景：
- SessionStart hook 被禁用或未生效
- 需要手动重新加载常驻契约
- 首次安装 plugin 后的 setup 步骤

## 3. 功能

1. **注入常驻契约**：读取并展示 `resident_contract_injectable.md` 的完整内容
2. **提示脚手架位置**：引导用户找到 `_TEMPLATE` 等脚手架资源（为 RM-2026-141 预留接口）

## 4. 使用方法

```
/setup
```

调用后，本 skill 会：
- 读取 `.harness/skills/setup/resident_contract_injectable.md`
- 将完整内容展示给你
- 提示：常驻契约已手动注入，可继续工作

## 5. 与 SessionStart hook 的关系

- **SessionStart hook 为主路径**：每 session 自动注入（零 friction）
- **setup skill 为降级路径**：hook 未启用或失效时手动调用
- **机制对齐**：两者注入的内容完全相同（共享 `resident_contract_injectable.md`）

与 CLAUDE.md「hook 失效退化路径」一致——hook 不可用则人工显式触发。

## 6. 注入内容

以下是常驻契约可重建子集（从 `resident_contract_injectable.md` 读取）：

---

<!-- 动态内容开始：实际调用时读取文件 -->

**注意**：在实际使用时，本 skill 会自动读取 `.harness/skills/setup/resident_contract_injectable.md` 并展示完整内容。

如果你看到此消息，说明正在阅读 skill 定义本身。实际调用 `/setup` 时，会看到完整的常驻契约内容（约 140 行）。

<!-- 动态内容结束 -->

---

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
A: 检查 `.harness/skills/setup/resident_contract_injectable.md` 是否存在且可读。

**Q: SessionStart hook 和 setup skill 哪个优先？**  
A: SessionStart hook 为主路径（自动）；setup skill 为降级路径（手动）。推荐依赖 hook，仅在 hook 失效时手动调用 skill。

**Q: 两者注入的内容是否一致？**  
A: 完全一致，共享同一源文件 `resident_contract_injectable.md`（避免双源漂移）。
