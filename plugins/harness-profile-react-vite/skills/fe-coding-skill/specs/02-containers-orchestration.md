---
layer: containers / orchestration
rules: ES-FE-1, ES-FE-2, FE-4, GEN-4
version: 1.0.0
updated: 2026-06-28
---

# Spec · Containers / Orchestration 层（React + Vite + TypeScript）

> 后端对标层：`coding-skill/specs/03-service-contracts.md`（编排/业务委托边界）。BE「service 编排 repository/adapter、router 仅依赖此层」↔ FE「container 编排 components + 调 hooks/services、承接页面级状态」。容器是 UI 与逻辑/数据之间的**编排接缝**，本身只委托不堆业务。

## 适用层

`src/<app>/containers/` 下的容器组件（`PascalCase.tsx`）。职责：**编排** UI（组合 `components/`）+ **调** `hooks/`（取状态/副作用）/ `services/`（经 hook 间接取数据）+ 承接**页面级状态**，把 hook 返回的数据/handler 透传给纯展示组件。依赖矩阵：containers 可依赖 `components`/`hooks`/`services`/`model`（单向向下 ES-FE-1）。

## 必守约束

| 规则 | 要求 |
|---|---|
| ES-FE-1 | 分层单向向下：容器调 `hooks`/`services`、组合 `components`；**不被 components 反向依赖**（components 经 props 由容器注入） |
| ES-FE-2 | 禁逆向依赖：`services`/`hooks` **不得** `import` 容器；逆向引用即违规 |
| GEN-4 | 容器**只编排+委托**：业务逻辑在 hooks、外部调用在 services；容器不堆业务、**不直接 `fetch`**（= 后端 CODE-003 编排瘦身的 FE 载体） |
| FE-4 | 组件分层遵 ES-FE-1~5（容器是编排层、非纯展示层、非数据层） |

## 编码要点

1. 容器组合纯展示 `component` + 调 `useXxx` hook 取数据/副作用；把 hook 返回的 `data`/`handler` 经 **props 透传**给 `<component>`。
2. **外部数据获取下沉 hooks → services**：容器**不直接 `fetch`**、不构造 HTTP 客户端；需要数据时调 hook，由 hook 经 service 取（超时/降级在 services 层 · ES-FE-5）。
3. 页面级状态（查询参数、加载态、选中项）放容器或其 hook，**不下放**到纯展示 component。
4. 容器内不堆业务规则（如折扣/聚合计算）——业务逻辑归 hooks/services，容器只做"取 → 编排 → 透传"的接线。
5. 命名 `PascalCase.tsx`；props 显式 TS 类型，禁 `any` 滥用（FE-1 邻接约束）。

## 正例 / 反例

```tsx
// 正例：容器调 hook（hook 内调 service），结果单向向下透传给纯展示组件
export function PriceQueryContainer({ skuId }: { skuId: string }) {
  const { data, loading } = usePriceQuery(skuId);   // hook 取状态；hook 内调 priceService
  if (loading) return <Spinner />;
  return <PriceCard priceCents={data.priceCents} />; // 数据经 props 注入纯展示组件
}

// 反例 A：容器直接 fetch，绕过 services 层（违 GEN-4 / 分层下沉）
export function PriceQueryContainer({ skuId }: { skuId: string }) {
  const [data, setData] = useState(null);
  useEffect(() => { fetch(`/api/prices/${skuId}`).then(/* ... */); }, [skuId]); // 应下沉 hooks→services
  return <PriceCard priceCents={data?.priceCents} />;
}

// 反例 B：services 逆向 import 容器（违 ES-FE-2 逆向依赖）
// services/priceService.ts
import { PriceQueryContainer } from '../containers/PriceQueryContainer'; // 禁止：下层引用上层
```

## 完成判据

- 依赖方向检查通过：容器 → `hooks`/`services`/`components` 单向向下，无逆向 import（services/hooks 未 import 容器）；
- 容器**无直接 `fetch`** / 无 HTTP 客户端构造（外部调用已下沉 services）；
- 容器无大段业务逻辑（业务在 hooks/services · GEN-4）；
- 阶段 4 评审清单 ES-FE-1 / ES-FE-2 / GEN-4 无违反。
