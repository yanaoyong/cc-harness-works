import { usePriceQuery } from '../hooks/usePriceQuery';
import { PriceCard } from '../components/PriceCard';
import { formatCents } from '../utils/formatCents';

/**
 * PriceQueryContainer 容器组件
 * 职责：编排 UI + 调 hooks 取数据，把数据透传给纯展示组件
 * 禁止：直接 fetch（外部调用下沉 hooks → services）
 */
interface PriceQueryContainerProps {
  skuIds: string[];
}

export function PriceQueryContainer({ skuIds }: PriceQueryContainerProps) {
  // 调用 hook 获取数据和状态（hook 内调 priceService）
  const { items, loading, error, totalCents } = usePriceQuery(skuIds);

  // 加载态
  if (loading) {
    return <div style={{ padding: '16px' }}>加载中...</div>;
  }

  // 错误态
  if (error) {
    return (
      <div style={{ padding: '16px', color: '#d00' }}>
        查询失败: {error}
      </div>
    );
  }

  // 空数据态
  if (items.length === 0) {
    return <div style={{ padding: '16px' }}>暂无数据</div>;
  }

  // 数据态：编排 UI，数据经 props 单向向下透传给纯展示组件
  return (
    <div style={{ padding: '16px' }}>
      <h2 style={{ marginBottom: '16px' }}>价格查询结果</h2>
      <div>
        {items.map((item) => (
          <PriceCard
            key={item.skuId}
            skuId={item.skuId}
            priceCents={item.priceCents}
            onSelect={(id) => console.log('选中:', id)} // 交互处理在容器层
          />
        ))}
      </div>
      <div
        style={{
          marginTop: '16px',
          padding: '12px',
          background: '#f0f0f0',
          borderRadius: '4px',
          fontWeight: 'bold',
        }}
      >
        总价: {formatCents(totalCents)}
      </div>
    </div>
  );
}
