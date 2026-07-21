# agents/ —— Agent 角色定义

> 存放编排中枢 Agent 定义（`.harness/` 厂商无关层）。
> 规范：`docs/stage-01-Harness体系建设/02-体系设计/04-编排中枢-ApplicationOwner定义规范.md`（+ `docs/stage-01-Harness体系建设/02-体系设计/03-自有Harness体系设计规范.md §4` 角色矩阵）。
> 状态：**已落地**（Owner）；执行/评判/治理子角色见 `.claude/agents/` 桥接。

## 本目录制品

| 文件 | 角色 | 职责 | 状态 |
|---|---|---|---|
| `application-owner.md` | 编排中枢 Owner | 与人交互、全流程调度、验收 | ✅ 已落地 |

## 角色矩阵与桥接位置

| 角色 | 职责 | 定义位置 | 状态 |
|---|---|---|---|
| Owner（编排） | 调度、验收、对人沟通 | **本目录** `application-owner.md` | ✅ |
| Generator（执行） | 需求产出 / 编码 / 写测试 | `.claude/agents/generator.md` | ✅ 桥接 |
| Reviewer（评判） | 计划 / 执行 / 单测评审 | `.claude/agents/reviewer.md` | ✅ 桥接 |
| Entropy（治理·可选） | 熵清理 / drift 检测 | `.claude/agents/entropy.md` | ✅ 桥接 |

> 铁律：**执行与评判分离**（`docs/stage-01-Harness体系建设/02-体系设计/04-编排中枢-ApplicationOwner定义规范.md §4`）。Owner 经项目根 `CLAUDE.md` `@导入` 生效；子 Agent 由 Owner 委派加载（`docs/stage-01-Harness体系建设/04-运行手册/12-运行时集成-ClaudeCode桥接规范.md`）。
> 全量制品说明：`docs/_meta-跨阶段/00-全项目制品总览.md`。
