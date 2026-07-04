---
layer: schemas / DTO
rules: CODE-001, R-001
version: 1.0.0
updated: 2026-06-02
---

# Spec · Schemas（Pydantic 模型）

## 适用层

`src/<app>/schemas/` 或 `models/dto.py`；定义 API 与 service 边界的结构化数据。

## 必守约束

| 规则 | 要求 |
|---|---|
| CODE-001 / R-001 | 金额字段命名清晰（如 `price_cents: int`），**禁止 `float` 表示金额** |
| — | 字段与 `spec.md` 协议一致；新增字段须向后兼容或版本化 |

## 编码要点

1. 继承 `pydantic.BaseModel`；必要时用 `Field(..., ge=0)` 约束非负分。
2. 请求/响应分离：`BatchPriceRequest` / `BatchPriceResponse`。
3. 可选字段用 `Optional` 或默认值；枚举用 `Enum`。
4. 不在 Schema 内写 IO 或业务计算。

## 正例 / 反例

```python
class PriceItem(BaseModel):
    sku_id: str
    price_cents: int  # 分

class BatchPriceRequest(BaseModel):
    sku_ids: list[str] = Field(..., min_length=1)

# 反例
class PriceItem(BaseModel):
    price: float  # 违反 CODE-001
```

## 完成判据

- 所有金额相关字段为 `int`（分）或明确非金额语义；
- OpenAPI 生成字段名与 spec 一致（见 `08-openapi.md`）。
