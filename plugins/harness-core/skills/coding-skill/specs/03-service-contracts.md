---
layer: service contracts
rules: CODE-003, ES-003
version: 1.0.0
updated: 2026-06-02
---

# Spec · Service 契约与实现边界

## 适用层

`src/<app>/service/` 包：对外暴露的业务函数/类；router 仅依赖此层公开 API。

## 必守约束

| 规则 | 要求 |
|---|---|
| CODE-003 | **全部业务逻辑**在 service；可组合 repository 与 adapter |
| ES-003 | service 可依赖 repository、adapter；**禁止** service import api/router |

## 编码要点

1. 用纯函数或小型 `class XxxService` 封装用例；构造函数注入 repository/adapter（便于测试）。
2. 函数签名使用 `schemas` 类型或领域类型，不暴露 FastAPI 类型。
3. 异步：若 router 为 `async`，service 内 IO 用 `async def` + `await` 保持一致。
4. 在 service 层做金额整数运算（分），避免浮点误差。

## 正例 / 反例

```python
async def batch_query(sku_ids: list[str]) -> BatchPriceResponse:
    rows = await price_repository.find_by_skus(sku_ids)
    return BatchPriceResponse(items=[...])

# 反例：service 返回裸 dict 且无类型，或依赖 Request 对象
async def batch_query(request: Request): ...
```

## 完成判据

- router 调用的每个端点均有对应 service 入口；
- service 无 FastAPI/Starlette 导入（测试可 mock repository）。
