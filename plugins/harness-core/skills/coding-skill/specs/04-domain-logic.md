---
layer: domain / service logic
rules: CODE-001, CODE-003, CODE-007
version: 1.0.0
updated: 2026-06-02
---

# Spec · 领域业务逻辑

## 适用层

`service/` 内纯业务规则：询价、折扣、聚合、校验等领域行为。

## 必守约束

| 规则 | 要求 |
|---|---|
| CODE-001 | 金额运算用 **整数分**；乘折扣用整数运算 `(price_cents * discount_bps) // 10000` |
| CODE-003 | 复杂流程可拆私有函数，但仍在 service 包内 |
| CODE-007 | 复用已有 `utils/money.py` 等，不重复实现分↔元转换 |

## 编码要点

1. 明确领域术语与 `spec.md` 一致（SKU、批量、封顶价等）。
2. 分支与边界：空列表、未知 SKU、外部降级后的默认值。
3. 日志记录业务关键决策点（CODE-004 SHOULD），不打印敏感数据。
4. 单元测试优先覆盖本层（阶段 5）。

## 正例 / 反例

```python
def apply_discount_bps(price_cents: int, discount_bps: int) -> int:
    return (price_cents * discount_bps) // 10000

# 反例
def apply_discount(price_cents: int, rate: float) -> float:
    return price_cents * rate / 100  # 浮点金额
```

## 完成判据

- 业务规则与 spec 验收项一一可测；
- 无 `float` 存储或传递金额；
- 评审时 T1/T5 类陷阱已规避。
