import type { PriceItem } from '../model/price';

/**
 * 价格服务层：对后端 API 的调用封装
 * 必须设置超时 + 降级（FE-3 / ES-FE-5 / GEN-2）
 */

/**
 * 通用 HTTP 客户端：封装 fetch + AbortController 超时 + 降级
 * @param url 请求 URL
 * @param fallback 降级返回值
 * @param timeoutMs 超时毫秒数（默认 3000ms）
 * @returns 成功时返回解析的 JSON，失败时返回 fallback
 */
async function getJson<T>(
  url: string,
  fallback: T,
  timeoutMs: number = 3000
): Promise<T> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs); // 超时取消

  try {
    const response = await fetch(url, { signal: ctrl.signal });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    return (await response.json()) as T;
  } catch (error) {
    // 降级：返回 fallback，不静默吞错（GEN-6）
    console.warn(`[priceService] 请求失败，降级返回空数据:`, error);
    return fallback;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * 批量查询价格
 * @param skuIds SKU ID 列表
 * @param signal 可选的外部 AbortSignal（用于组件卸载时取消）
 * @returns 价格项列表，失败时降级返回空数组
 */
export async function batchQueryPrices(
  skuIds: string[],
  signal?: AbortSignal
): Promise<PriceItem[]> {
  // 模拟 API 端点（实际项目中应从环境变量读取 base URL）
  const url = `/api/prices/batch?skuIds=${skuIds.join(',')}`;

  // 如果外部传入 signal 且已取消，直接返回降级值
  if (signal?.aborted) {
    return [];
  }

  const data = await getJson<{ items: PriceItem[] }>(url, { items: [] });

  // 类型映射：确保返回领域模型，字段对齐后端 schema（FE-7）
  return data.items.map((item): PriceItem => ({
    skuId: item.skuId,
    priceCents: item.priceCents, // 保持整数分（GEN-1）
  }));
}

export const priceService = {
  batchQuery: batchQueryPrices,
};
