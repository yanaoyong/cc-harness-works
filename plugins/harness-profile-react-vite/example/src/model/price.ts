/**
 * 价格项领域模型
 * 金额字段用整数分（priceCents: number），与后端 schema 对齐
 */
export interface PriceItem {
  skuId: string;
  priceCents: number; // 整数分单位，禁浮点存金额（FE-2 / GEN-1）
}
