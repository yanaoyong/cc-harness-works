# rules/ —— 规则体系（① 标准是什么）

> 稳定不变约束（工程结构、流程、编码规范）。
> 规范：`docs/stage-01-Harness体系建设/02-体系设计/05-Rules规则体系规范.md`。
> 状态：已落地；**Python 模板栈**（2026-06-02 阶段 B）见各文件 `stack` 与 `docs/stage-01-Harness体系建设/05-技术栈与工具/14-附录-Step0`。

## 规则索引（供编排中枢引用 · 对接 docs/stage-01-Harness体系建设/02-体系设计/04-编排中枢-ApplicationOwner定义规范.md 模块二）

| 规则文件 | 职责 | 触发场景 | 更新频率 | enforce | 是否 L1 常驻 | 状态 |
|---|---|---|---|---|---|---|
| `工程结构.md` | 目录/分层（api→service→repository） | 全程 | 稳定 | mechanical+manual | 是 | ✅ Python 1.1 |
| `开发流程规范.md` | 流程/HITL；pytest 回退路由 | 全程 | 稳定 | manual+mechanical | 是 | ✅ Python 1.1 |
| `项目编码规范.md` | Python/FastAPI（int 分、httpx 超时） | 编码/评审 | 偶尔 | mechanical+manual | 是 | ✅ Python 1.1 |

> 规则可判定性分级（MUST 机械 / MUST 人工 / SHOULD / INFO）与硬约束登记表见 `docs/stage-01-Harness体系建设/02-体系设计/05-Rules规则体系规范.md`。
