---
layer: hooks
rules: ES-FE-1, ES-FE-2, ES-FE-3, FE-2, FE-4, FE-7, GEN-1, GEN-4, GEN-6
version: 1.0.0
updated: 2026-06-28
---

# Spec · Hooks 逻辑层（业务逻辑 / 副作用 / 状态管理）

> 后端对标层：`coding-skill/specs/04-domain-logic.md`（领域业务层）。BE「领域规则下沉 service、金额整数分、复用 utils」(CODE-001/003/007) ↔ FE「业务逻辑/副作用/状态封装在 `useXxx` hook、金额整数分、单向向下不逆向」(ES-FE-1/FE-4/GEN-4)。本层同时承接「前端状态形状的定义、不可变更新与同步」——状态即 FE 的"数据 schema"，故合并 RM-2026-133 原 hooks-logic + state-management 两份为本份。

## 适用层

`src/<app>/hooks/`（及可选 `store/`）：可复用业务逻辑、副作用封装（`useXxx`）与页面级/跨组件状态的建模、更新、同步。containers 依赖此层编排页面行为并承接状态；components 不直接持有业务逻辑/业务状态，统一下沉至此，经 props 接收派生只读视图。依赖矩阵：hooks 可依赖 `services`/`model`/`utils`（单向向下）。

## 必守约束

| 规则 | 要求 |
|---|---|
| ES-FE-1 | hooks 单向向下——可依赖 `services`/`model`/`utils`；**禁止** import containers/components |
| ES-FE-2 | 禁逆向依赖：hooks 不得被 services 反向 import；hooks 不得 import containers（逆向引用即违规） |
| ES-FE-3 / FE-4 / GEN-4 | 组件（components）保持纯展示；业务逻辑/副作用（请求编排、计算、订阅）与业务状态封装在 hooks（对应后端表现层瘦身范式 CODE-003） |
| FE-2 / GEN-1 | hooks 内金额用整数分（`priceCents: number` 整数语义）；折扣等用整数运算，禁浮点存/算金额 |
| FE-7 | 状态形状（state shape）的领域字段与后端 `model/` schema 对齐（金额单位/字段名跨栈一致 · 联调契约 S-007） |
| GEN-6 | 异常分层不吞底层错误：捕获后转领域错误态供 container 渲染，禁空 `catch {}` |

## 编码要点

1. 命名 `useXxx`（ES-FE-4 / FE-6）；一个 hook 聚焦单一职责（如 `usePriceQuery` 只管询价编排，不混分页 UI 态）。
2. 副作用经 `useEffect`/`useCallback` 显式声明依赖数组；清理函数处理订阅/定时器/`AbortController` 取消，避免泄漏。
3. 调后端经 services 层（`xxxService`），hooks 不直接 `fetch`/`axios`（外部调用归 services · ES-FE-1/ES-FE-5）。
4. 金额整数运算在 hooks 完成（如折扣 `Math.floor(priceCents * discountBps / 10000)`），不向下传浮点。
5. **状态管理**：局部简单态用 `useState`；含多动作/转移的复杂态用 `useReducer`（reducer 纯函数、按 action 收敛）；跨页共享态用集中 store（context + reducer 或轻量 store）。状态的**持久化/跨标签同步**（如 localStorage / `storage` 事件）经专用 `useXxx` hook 封装收口，不散落进组件（与"业务逻辑下沉 hooks"同范式）。
6. **不可变更新**：禁止原地 mutate（`state.items.push(...)`），一律返回新对象/新数组（`[...items, next]` / `{ ...state, field }`）。
7. 状态形状字段与后端 schema 一一对齐（FE-7）：字段名、金额单位（分）、可空性与后端 `model/` 一致，避免联调漂移；派生数据用 `useMemo` 计算，不冗余存 state（单一事实源）。

## 正例 / 反例

```tsx
// 正例：业务逻辑/副作用/状态封装在 hook；useReducer 不可变更新；金额整数分；调 service 不直接 fetch
interface PriceState { items: { skuId: string; priceCents: number }[] }
type Action = { type: 'set'; items: PriceState['items'] };
function reducer(state: PriceState, action: Action): PriceState {
  switch (action.type) {
    case 'set':
      return { ...state, items: action.items }; // 新对象，不 mutate
  }
}
export function usePriceQuery(skuIds: string[]) {
  const [state, dispatch] = useReducer(reducer, { items: [] });
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    const ctrl = new AbortController();
    priceService
      .batchQuery(skuIds, ctrl.signal)               // 外部调用归 services
      .then((items) => dispatch({ type: 'set', items }))
      .catch((e) => setError(String(e)));            // 不吞错，转领域错误态
    return () => ctrl.abort();                        // 清理副作用
  }, [skuIds]);
  const totalCents = useMemo(
    () => state.items.reduce((s, it) => s + it.priceCents, 0), // 整数分运算
    [state.items],
  );
  return { items: state.items, totalCents, error };
}

// 反例①：hook 直接 fetch（越层，外部调用应在 services）
function usePrice(id: string) {
  return fetch(`/api/prices/${id}`).then((r) => r.json());
}
// 反例②：浮点金额 + 原地 mutate（违 FE-2/GEN-1 + 不可变更新）
const total = priceCents * 0.85;   // 应整数运算
state.items.push(next);            // 破坏不可变性，React 不重渲染
// 反例③：状态字段名/单位与后端 schema 不一致（违 FE-7）
const [s, setS] = useState({ price: 99.99 });
```

## 完成判据

- 每个被 component/container 复用的业务逻辑/业务状态均有对应 `useXxx`，components 内无业务计算、无散落业务状态机；
- hooks 无 containers/components 导入（依赖方向检查无逆向 · ES-FE-1/ES-FE-2）；
- 金额全程整数分，无 `float` 参与金额运算；状态字段名/单位与后端 `model/` schema 对齐（FE-7）；
- 状态更新全程不可变（无原地 mutate），派生值经 `useMemo` 计算而非冗余存储；
- 副作用 hook 均有清理函数，无未取消的请求/订阅；异常未被静默吞掉（GEN-6）。
