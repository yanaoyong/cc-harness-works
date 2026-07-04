---
layer: openapi / docs
rules: CODE-001
version: 1.0.0
updated: 2026-06-02
---

# Spec · OpenAPI / API 文档

## 适用层

FastAPI 自动生成的 `/docs`、`/redoc` 及导出的 OpenAPI JSON；与 `spec.md` 对外协议一致。

## 必守约束

| 规则 | 要求 |
|---|---|
| — | 路径、方法、字段名与 `spec.md` 一致；金额字段文档注明**单位：分** |
| CODE-001 | Schema 示例不出现 `float` 金额 |

## 编码要点

1. 为路由设置 `summary`、`description`、`response_model`。
2. 使用 `tags` 分组；错误响应用 `responses={404: {...}}` 声明。
3. 版本化：必要时 `/v1` 前缀与 spec 对齐。
4. 交付前人工核对 Swagger 与 spec 差异。

## 完成判据

- OpenAPI 中批量询价等核心接口可浏览且模型正确；
- 阶段 10 交付时文档链接或导出路径已写入 `summary.md`（若需要）。
