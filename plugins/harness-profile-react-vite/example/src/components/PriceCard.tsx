import { formatCents } from '../utils/formatCents';

/**
 * PriceCard 组件的 Props 接口
 * 金额用整数分（FE-2 / GEN-1）
 */
interface PriceCardProps {
  skuId: string;
  priceCents: number; // 整数分
  onSelect?: (skuId: string) => void; // 可选回调
}

/**
 * PriceCard 纯展示组件
 * 职责：仅渲染 props，交互经回调上抛（ES-FE-3）
 * 禁止：副作用、直接 fetch、业务逻辑
 */
export function PriceCard({ skuId, priceCents, onSelect }: PriceCardProps) {
  return (
    <div
      className="price-card"
      style={{
        border: '1px solid #ddd',
        padding: '16px',
        margin: '8px',
        borderRadius: '4px',
        cursor: onSelect ? 'pointer' : 'default',
      }}
      onClick={() => onSelect?.(skuId)}
    >
      <div style={{ fontWeight: 'bold', marginBottom: '8px' }}>
        SKU: {skuId}
      </div>
      <div style={{ fontSize: '20px', color: '#e63946' }}>
        {formatCents(priceCents)} {/* 格式化在 utils，不在组件内浮点运算 */}
      </div>
    </div>
  );
}
