---
layer: api / router
rules: CODE-003, CODE-006, ES-003
version: 1.0.0
updated: 2026-06-02
---

# Spec · API / Router 层（FastAPI）

## 适用层

`src/<app>/api/` 或 `routers/` 下的 `APIRouter` 模块；仅处理 HTTP 边界。

## 必守约束

| 规则 | 要求 |
|---|---|
| CODE-003 | 路由函数 **≤ 编排**：校验入参 → 调 `service` → 映射响应；禁止批量询价/折扣等业务 |
| CODE-006 | 捕获 `service` 业务异常并映射为 `HTTPException`；禁止裸 `except:` |
| ES-003 | 不得 `import` repository；依赖方向 api → service |

## 编码要点

1. 使用 `APIRouter(prefix=..., tags=[...])` 按领域拆分路由文件。
2. 入参/出参使用 Pydantic 模型（见 `02-schemas.md`），路径参数用类型注解。
3. 统一异常：404/400/502 等与 `spec.md` 约定一致。
4. 不在 router 内构造 httpx 客户端或访问 DB。

## 正例 / 反例

```python
# 正例
@router.post("/prices/batch")
async def batch_prices(body: BatchPriceRequest) -> BatchPriceResponse:
    return await price_service.batch_query(body.sku_ids)

# 反例：router 内算折扣
@router.post("/prices/batch")
async def batch_prices(body: BatchPriceRequest):
    results = []
    for sku in body.sku_ids:
        p = db.fetch(sku)
        results.append(p * 0.9)  # 业务逻辑应进 service
    return results
```

## 完成判据

- 所有新路由已委托对应 `service` 函数；
- `ruff check` 无新增 MUST 级问题；
- 阶段 4 评审清单 CODE-003 无违反。
