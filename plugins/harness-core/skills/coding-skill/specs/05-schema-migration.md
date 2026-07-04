---
layer: schema / migration
rules: ES-003
version: 1.0.0
updated: 2026-06-02
---

# Spec · Schema / 迁移（按需）

## 适用层

使用关系型 DB 时的 `migrations/`、`alembic/` 或 SQL 脚本。**模板仓 demo 可无 DB，本 Spec 标 N/A 即可。**

## 必守约束

| 规则 | 要求 |
|---|---|
| ES-003 | 迁移脚本不被 api 层直接引用；经 repository 访问数据 |
| — | 金额列类型用 **整数分**（`BIGINT`/`INTEGER`），禁止 `DOUBLE PRECISION` 存价 |

## 编码要点

1. 迁移可回滚或注明不可逆；命名含日期/序号。
2. 索引与查询路径对齐 `spec.md` 批量查询场景。
3. 种子数据金额以分为单位。
4. 无 DB 的纯内存/HTTP demo：在 `coding_report` 注明 **N/A**，跳过本层。

## 完成判据

- 有 DB 时：迁移可应用且 repository 测试通过；
- 无 DB 时：文档注明 N/A，不阻塞阶段 3 门禁。
