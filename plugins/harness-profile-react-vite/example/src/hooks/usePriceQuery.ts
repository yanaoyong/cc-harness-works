import { useEffect, useReducer, useMemo } from 'react';
import { priceService } from '../services/priceService';
import type { PriceItem } from '../model/price';

/**
 * 价格查询状态
 */
interface PriceState {
  items: PriceItem[];
  loading: boolean;
  error: string | null;
}

/**
 * 状态动作（不可变更新）
 */
type PriceAction =
  | { type: 'loading' }
  | { type: 'success'; items: PriceItem[] }
  | { type: 'error'; error: string };

/**
 * Reducer：纯函数，不可变更新（禁止原地 mutate）
 */
function priceReducer(state: PriceState, action: PriceAction): PriceState {
  switch (action.type) {
    case 'loading':
      return { ...state, loading: true, error: null };
    case 'success':
      return { ...state, loading: false, items: action.items, error: null };
    case 'error':
      return { ...state, loading: false, error: action.error };
    default:
      return state;
  }
}

/**
 * 价格查询 Hook
 * 封装业务逻辑：调用 priceService 获取数据，管理加载/错误状态
 *
 * @param skuIds SKU ID 列表
 * @returns 价格项、加载状态、错误信息、总金额
 */
export function usePriceQuery(skuIds: string[]) {
  const [state, dispatch] = useReducer(priceReducer, {
    items: [],
    loading: false,
    error: null,
  });

  useEffect(() => {
    // 空列表不发请求
    if (skuIds.length === 0) {
      return;
    }

    const ctrl = new AbortController();

    dispatch({ type: 'loading' });

    // 调用 services 层，不在 hook 内直接 fetch（ES-FE-1）
    priceService
      .batchQuery(skuIds, ctrl.signal)
      .then((items) => {
        if (!ctrl.signal.aborted) {
          dispatch({ type: 'success', items });
        }
      })
      .catch((error) => {
        if (!ctrl.signal.aborted) {
          // 不吞底层错误，转领域错误态（GEN-6）
          dispatch({ type: 'error', error: String(error) });
        }
      });

    // 清理函数：组件卸载时取消请求
    return () => {
      ctrl.abort();
    };
  }, [skuIds.join(',')]); // 依赖数组：skuIds 变化时重新请求

  // 派生值：总金额（整数分运算，useMemo 避免重复计算）
  const totalCents = useMemo(
    () => state.items.reduce((sum, item) => sum + item.priceCents, 0),
    [state.items]
  );

  return {
    items: state.items,
    loading: state.loading,
    error: state.error,
    totalCents, // 整数分（GEN-1）
  };
}
