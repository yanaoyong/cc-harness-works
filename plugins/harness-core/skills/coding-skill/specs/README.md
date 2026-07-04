# coding-skill / specs/ —— 分层编码 Spec 索引

> 8 份分层编码规范，编码时**按当前所处层加载对应一份**（非全量）。
> 规范：`docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md §4` · 状态：**Python 正文已落地**（阶段 F，2026-06-02）。

| 层级 | Spec 文件 | 核心约束（高层） | 状态 |
|---|---|---|---|
| 表现层 | [`01-api-router.md`](01-api-router.md) | FastAPI 路由、校验、HTTP 异常映射 | ✅ |
| 应用层 | [`02-schemas.md`](02-schemas.md) | Pydantic 模型、请求/响应 DTO | ✅ |
| 应用层 | [`03-service-contracts.md`](03-service-contracts.md) | service 协议与实现边界 | ✅ |
| 业务层 | [`04-domain-logic.md`](04-domain-logic.md) | 业务封装、金额 `int`（分） | ✅ |
| 数据层 | [`05-schema-migration.md`](05-schema-migration.md) | 迁移/DDL（无 DB 可 N/A） | ✅ |
| 数据层 | [`06-repository.md`](06-repository.md) | 仓储模式，禁止 api 依赖 | ✅ |
| 适配层 | [`07-adapter.md`](07-adapter.md) | httpx 超时/降级 | ✅ |
| 文档层 | [`08-openapi.md`](08-openapi.md) | OpenAPI / FastAPI 文档 | ✅ |

> 每份 Spec 声明：适用层、必守约束（引用 `../../../rules/`）、正反例、完成判据。
> Java 历史用语（Controller/Mapper/`long`）见 `docs/stage-01-Harness体系建设/01-调研与提炼/01-文章提炼-Harness-Engineering实践.md`，**本仓以 Rules v1.1.0 为准**。
