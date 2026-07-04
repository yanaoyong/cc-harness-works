---
layer: repository
rules: ES-003, CODE-001
version: 1.0.0
updated: 2026-06-02
---

# Spec · Repository（持久化）

## 适用层

`src/<app>/repository/`：封装 DB/缓存访问；**禁止** Mapper 式 SQL 散落在 router。

## 必守约束

| 规则 | 要求 |
|---|---|
| ES-003 | repository **不得** import api/router；仅被 service 调用 |
| CODE-001 | 从存储读出金额为 `int` 分 |

## 编码要点

1. 接口清晰：`find_by_skus(ids: list[str]) -> list[PriceRow]`。
2. 无 ORM 时可用轻量 SQL/内存 dict；有 ORM 时保持 session 边界在 repository 内。
3. 不把 HTTP 或 Pydantic 模型传入 SQL 层（在 service 转换）。
4. 事务边界在 repository 或 service 显式声明。

## 正例 / 反例

```python
class PriceRepository:
    async def find_by_skus(self, sku_ids: list[str]) -> list[PriceRow]:
        ...

# 反例：repository 内 import APIRouter 或处理 HTTPException
```

## 完成判据

- service 仅通过 repository 访问持久化；
- 依赖方向检查无 api ← repository 逆向。
