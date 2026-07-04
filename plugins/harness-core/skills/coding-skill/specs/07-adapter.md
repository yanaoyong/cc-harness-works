---
layer: adapter
rules: CODE-002, R-002
version: 1.0.0
updated: 2026-06-02
---

# Spec · 外部适配器（httpx）

## 适用层

`src/<app>/adapter/` 或 `clients/`：调用外部 HTTP/RPC 服务。

## 必守约束

| 规则 | 要求 |
|---|---|
| CODE-002 / R-002 | **必须** `timeout=`（连接+读取）；失败时**降级**（默认价/空列表/缓存） |
| CODE-005 | 密钥从环境变量读取，禁止硬编码 |

## 编码要点

1. 使用 `httpx.AsyncClient(timeout=httpx.Timeout(3.0, connect=1.0))` 或等价配置。
2. 封装重试策略须有限次且总时长受控；禁止无超时轮询。
3. 记录外部错误码与 trace_id（CODE-004），不向用户泄露内部栈。
4. 单元测试 mock adapter，不依赖真实外网。

## 正例 / 反例

```python
async with httpx.AsyncClient(timeout=5.0) as client:
    try:
        r = await client.get(url)
        r.raise_for_status()
        return parse(r.json())
    except httpx.HTTPError:
        return default_price_list()  # 降级

# 反例
httpx.get(url)  # 无 timeout
```

## 完成判据

- 所有外部调用点有 timeout 与文档化降级行为；
- 阶段 4 评审清单 #3 通过。
