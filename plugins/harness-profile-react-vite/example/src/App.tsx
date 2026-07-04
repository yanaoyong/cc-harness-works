import { PriceQueryContainer } from './containers/PriceQueryContainer';

/**
 * App 根组件
 * 演示四层架构：Container → Hook → Service → API
 */
function App() {
  // 示例：查询三个 SKU 的价格
  const demoSkuIds = ['SKU-001', 'SKU-002', 'SKU-003'];

  return (
    <div style={{ fontFamily: 'sans-serif', maxWidth: '600px', margin: '0 auto' }}>
      <h1 style={{ padding: '16px', textAlign: 'center' }}>
        Harness React+Vite Example
      </h1>
      <p style={{ padding: '0 16px', color: '#666' }}>
        演示四层架构：Components（纯展示）→ Containers（编排）→ Hooks（逻辑）→ Services（数据/外部）
      </p>
      <PriceQueryContainer skuIds={demoSkuIds} />
    </div>
  );
}

export default App;
