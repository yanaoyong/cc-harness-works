---
layer: services
rules: ES-FE-2, ES-FE-5, FE-3, FE-4, FE-7, GEN-2, GEN-3, GEN-6, GEN-7
version: 1.0.0
updated: 2026-06-28
---

# Spec · Services 数据/外部访问层（API client + 超时·降级传输边界）

> 后端对标层：`coding-skill/specs/06-repository.md`（持久化访问收口）+ `07-adapter.md`（httpx 超时/降级）合并。FE 无独立"仓储/外部适配"二分，数据访问与外部调用统一收敛在 `services/`——故两后端层合并映射本份。FE 的 services 层是「数据/外部访问」收口点：对前端而言后端 API 即其"数据源"，故镜像 repository 的"封装访问、禁逆向依赖、返回领域模型"职责，并承接 adapter 的「外部 HTTP/RPC 调用必须设超时 + 降级」传输边界（GEN-2 的 FE 载体 · FE-3 / ES-FE-5）。

## 适用层

`src/<app>/services/`：对后端 API 的调用封装（`xxxService`）+ 统一 HTTP 传输适配器（底层 `httpClient`）。hooks/containers 经此层访问后端；**禁止** components 直接调用（外部访问统一收口于 services · ES-FE-3）。底层 client 封装 fetch/axios 的超时、降级、错误归一与公共配置，被各 `xxxService` 复用。

## 必守约束

| 规则 | 要求 |
|---|---|
| ES-FE-2 | services **不得** import containers/components；仅被 hooks/containers 调用（依赖单向向下） |
| FE-3 / ES-FE-5 / GEN-2 | **外部调用必设超时**（`AbortController` + `setTimeout` 取消，或 axios `timeout`）+ **失败降级**（默认值/空列表/缓存）——MUST 机械+人工 |
| FE-7 | 请求/响应类型与后端 `model/` schema 对齐（金额单位/字段名跨栈一致），返回**领域模型**而非裸 `Response`/`any` |
| FE-4 / GEN-4 | services 只做请求构造 + 响应解析 + 类型映射；业务编排在 hooks/containers，不在 service 内做页面逻辑 |
| GEN-3 | 令牌/密钥经环境变量（`import.meta.env`）注入，禁硬编码入库；敏感 header 不打日志 |
| GEN-6 | 不吞底层错误：超时/网络错误转可识别错误态上抛或降级，禁空 `catch {}` |
| GEN-7 | 复用统一 API client（base URL / 公共 header / 错误归一），不在各 service 重复造 fetch 样板 |

## 编码要点

1. 统一封装一个 `httpClient`：注入 base URL、公共 header、默认超时；所有 service 经它发请求（GEN-7 复用）。
2. **超时（MUST）**：fetch 用 `AbortController` + `setTimeout(() => ctrl.abort(), ms)`（或合并外部传入 signal）；axios 用 `timeout: ms`。禁止无超时请求。
3. **降级（MUST）**：超时/失败时返回文档化的默认值（空列表 / 缓存 / 降级标记 fallback），并记录可观测信息（结构化日志，不泄露密钥 · GEN-5）。重试须有限次且总时长受控（叠加超时上限），禁无界轮询。
4. 命名 `xxxService.ts`（ES-FE-4）；导出按用例命名的函数（`batchQuery`、`fetchPriceById`），签名用 `model/` 的 TS 类型；解析后端响应为领域模型并做字段映射，金额字段保持整数分（FE-2/GEN-1）。
5. 不向上层泄露传输层细节（不返回裸 `Response`/`AxiosResponse`/`AbortError`）；HTTP 错误转领域错误供 hooks 处理。
6. 不在 service 内读写 React 状态或 import 组件——保持纯数据访问，可独立单测（mock client）。

## 正例 / 反例

```ts
// 正例：统一 httpClient 设超时 + 失败降级；service 返回领域模型，类型对齐后端 schema
import type { PriceItem } from '../model/price';        // 与后端 schema 对齐（FE-7）

async function getJson<T>(url: string, fallback: T, ms = 3000): Promise<T> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), ms);     // 超时（AbortController + setTimeout）
  try {
    const r = await fetch(url, { signal: ctrl.signal });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return (await r.json()) as T;
  } catch {
    return fallback;                                     // 降级（fallback），不吞为静默
  } finally {
    clearTimeout(timer);
  }
}
// axios 等价：axios.get(url, { timeout: 3000 }).catch(() => fallback)

export const priceService = {
  async batchQuery(skuIds: string[], signal?: AbortSignal): Promise<PriceItem[]> {
    const data = await getJson<{ items: PriceItem[] }>('/api/prices/batch', { items: [] });
    return data.items.map((r): PriceItem => ({ skuId: r.skuId, priceCents: r.priceCents }));
  },
};

// 反例①：未设超时 + 无降级（违 FE-3/ES-FE-5/GEN-2 · MUST 机械+人工）
const data = await fetch(url).then((r) => r.json());     // 无 timeout / 无 fallback
// 反例②：service 返回裸 Response 且类型 any（泄露传输层 · 违 FE-7）
export async function getPrice(id: string): Promise<Response> {
  return fetch(`/api/prices/${id}`);
}
// 反例③：service import 组件（逆向依赖 · 违 ES-FE-2）+ 硬编码令牌（违 GEN-3）
import PriceCard from '../components/PriceCard';
fetch(url, { headers: { Authorization: 'Bearer sk-abc123' } });
```

## 完成判据

- 所有外部调用点均有超时（`AbortController`/axios `timeout`）与文档化降级（fallback）行为；无未设超时的 fetch/axios 调用（评审清单逐点核对 · MUST 机械+人工）；
- 每个被 hooks/containers 调用的后端用例均有对应 `xxxService` 函数，返回领域模型（非裸 Response/any）；
- services 无 containers/components 导入（依赖方向检查无逆向 · ES-FE-2）；
- 响应类型字段/金额单位与后端 `model/` schema 对齐（FE-7）；密钥经环境变量注入、无硬编码、不打日志（GEN-3）；
- 错误未被静默吞掉（降级或上抛领域错误，无空 `catch {}` · GEN-6）；service 可脱离 React 独立单测（mock client）。
