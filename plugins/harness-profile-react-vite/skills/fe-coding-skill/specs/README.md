# fe-coding-skill / specs/ —— FE 分层编码 Spec 索引

> **容器声明**：fe-coding-skill 的 `SKILL.md` / SOP 正文已由 **RM-2026-134** 补全（见 [`../SKILL.md`](../SKILL.md)）。本目录承载其 4 份分层 Spec：components/containers 两份由 RM-2026-132（S-005a）交付；hooks/services 两份由 RM-2026-133（S-005b）交付。

FE 编码时**按当前所处层加载对应一份**（非全量）；加载顺序与 `layeredSpecMapping`（FE 侧 · `BindingLayerContract` 三成员之一）对齐——按 `NN-` 前缀发现/排序、据本 README 注册项加载。

## FE ≈8 层规划全表

| FE 层 | Spec 文件 | 后端对标层 | 核心约束（高层） | 状态 |
|---|---|---|---|---|
| components（UI/展现） | [`01-components-ui.md`](01-components-ui.md) | 后端 api/router（表现层） | 纯展示 / 禁越层调后端 | ✅（RM-132） |
| containers（容器/编排） | [`02-containers-orchestration.md`](02-containers-orchestration.md) | 后端 service-contracts（编排/委托边界） | 单向向下 / 禁逆向 / 编排瘦身 | ✅（RM-132） |
| hooks（逻辑） | [`03-hooks-logic.md`](03-hooks-logic.md) | 后端 domain-logic（业务层） | 业务逻辑/副作用/状态封装在 `useXxx` / 金额整数分 | ✅（RM-133） |
| services（数据/外部） | [`04-services-external.md`](04-services-external.md) | 后端 repository+adapter（数据/适配层） | API client 单向向下 / 外部调用超时 + 降级 | ✅（RM-133） |

## 「≈8」口径说明

后端有 **8 份**分层 Spec：`01-api-router` / `02-schemas` / `03-service-contracts` / `04-domain-logic` / `05-schema-migration` / `06-repository` / `07-adapter` / `08-openapi`。FE（React+Vite）只有 **4 个实体分层**（components / containers / hooks / services），故 FE Spec 取「**≈8**」而非严格 8，对应关系如下：

- **后端 `02-schemas`（DTO/Pydantic）↔ FE `model/`（TS 类型层）**：FE 类型随各层就近声明（props/hook 返回/service 出入参均引 `model/`），**不单列独立 Spec**——故 schemas 在 FE 侧映射为类型层、并入各层 Spec。
- **后端 `06-repository` + `07-adapter` 合并 ↔ FE `services` 层**：FE 无独立"仓储/外部适配"二分，数据访问与外部调用统一收敛在 `services/`（超时+降级 · ES-FE-5），故两后端层**合并映射**一份 FE `04-services-external.md`。
- **后端 `05-schema-migration`（DB 迁移/DDL）/ `08-openapi`（接口文档）= 后端数据/文档层，FE 无对应实体层（N/A）**：前端不持久化 DB、不产 OpenAPI 文档，这两层在 FE 模型下标 **N/A**。

由此，FE 四份分层 Spec（components/containers/hooks/services）即与后端 8 份**对等**（DTO 并入类型层、repository+adapter 合并、migration+openapi N/A）。RM-2026-132 覆盖 components/containers 子集；RM-2026-133 补齐 hooks/services（本卡 · S-005b）。

> **`layeredSpecMapping()` Spec 来源**：本索引即 FE 侧 `layeredSpecMapping()` 的 Spec 来源（与后端同范式——「实现」由索引体现而非独立代码文件）；表内 `Spec 文件` 列 = `SpecLayer.path`，`FE 层` 列对应 `SpecLayer.layer`。签名 `layeredSpecMapping(): SpecLayer[]`（`SpecLayer = {layer, path}`）由 RM-2026-127 已定，本卡只填实值不改签名。
>
> 每份 Spec 声明：适用层、必守约束（引用 `plugins/harness-core/rules/` FE-x/ES-FE-x）、编码要点、正反例、完成判据。
