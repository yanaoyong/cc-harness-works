---
layer: components / ui
rules: ES-FE-1, ES-FE-3, ES-FE-4, FE-1, FE-2, FE-4, FE-6, GEN-4
version: 1.0.0
updated: 2026-06-28
---

# Spec · Components / UI 层（React + Vite + TypeScript）

> 后端对标层：`coding-skill/specs/01-api-router.md`（表现层）。BE「router 瘦身 · 只编排不堆业务」(CODE-003) ↔ FE「组件纯展示 · 不持副作用/不调后端」(ES-FE-3 / GEN-4)。

## 适用层

`src/<app>/components/` 下的纯展示组件（`PascalCase.tsx`）。职责**仅渲染 props**：把容器/hook 传入的数据映射为 UI，把用户交互经回调 props 上抛。组件**不持副作用、不直接发起 API 调用、不持有页面级状态**——这些归 containers/hooks（依赖矩阵：components 仅依赖 `model/`、`utils/`）。

## 必守约束

| 规则 | 要求 |
|---|---|
| ES-FE-3 | 组件**纯展示**：无副作用、无 `useEffect` 拉数据、无直接 API 调用；业务逻辑在 hooks/containers，外部调用在 services |
| ES-FE-1 / FE-4 | **不得越层 `import` services**（components 仅依赖 `model`/`utils`）；分层单向向下，数据经 props 由 containers/hooks 注入 |
| GEN-4 | 表现层只做渲染+交互上抛，逻辑下沉 hooks/containers（= 后端 CODE-003 router 瘦身的 FE 载体） |
| FE-1 | TypeScript strict；props 用显式 interface/type，禁 `any` 滥用 |
| FE-2 | 若渲染金额，用整数最小单位 `priceCents: number`（整数分），**禁浮点存金额**；格式化逻辑放 `utils/` |
| FE-6 | 命名 `PascalCase.tsx`；禁裸 `console` 打生产路径（结构化日志） |

## 编码要点

1. props 入参声明显式 TS interface（如 `interface PriceCardProps { priceCents: number }`），禁 `any`；可选回调用 `onXxx?: (...) => void` 形态。
2. 用户交互（点击/输入）经 **callback props 上抛**给容器处理，组件自身不决策业务分支。
3. 金额以 `priceCents: number`（整数分）入参渲染；展示用格式化（如 `formatCents` 工具）放 `utils/`，组件内不做浮点金额运算。
4. **禁在组件内 `fetch` / `useEffect` 拉数据**；所需数据一律由容器/hook 经 props 注入。
5. 组件保持无状态或仅持纯 UI 局部状态（如展开/收起），页面级数据状态不在此层。

## 正例 / 反例

```tsx
// 正例：纯展示组件，经 props 收数据，交互经回调上抛
interface PriceCardProps {
  priceCents: number;            // 整数分（FE-2）
  onSelect?: (skuId: string) => void;
}
export function PriceCard({ priceCents, onSelect }: PriceCardProps) {
  return (
    <div className="price-card" onClick={() => onSelect?.('sku-1')}>
      {formatCents(priceCents)}   {/* 格式化在 utils，不在组件内浮点运算 */}
    </div>
  );
}

// 反例：组件内越层调后端 + 浮点金额
export function PriceCard() {
  const [price, setPrice] = useState<number>(99.99);   // 浮点存金额，违 FE-2/GEN-1
  useEffect(() => {
    fetch('/api/prices').then(r => r.json()).then(d => setPrice(d.price)); // 越层调后端，违 ES-FE-3/ES-FE-1
  }, []);
  return <div>{price}</div>;
}
```

## 完成判据

- 组件无 `services` import、无副作用（无 `useEffect` 拉数据、无 `fetch`）；数据全部经 props 注入；
- import 方向检查通过（components 仅依赖 `model`/`utils`，未越层调 services）；
- 金额字段为整数分（无浮点金额）；命名 `PascalCase.tsx`、无裸 `console` 打生产；
- 阶段 4 评审清单 ES-FE-3 / FE-4 无违反。
