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

## 完整指南

分发渠道、双仓同步、认证排障等完整说明见项目分发指南（plugin-distribution-guide）。
