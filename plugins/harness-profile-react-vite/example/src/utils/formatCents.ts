/**
 * 金额格式化工具：整数分 → 显示字符串（如 "¥99.99"）
 * 不做浮点金额运算，纯格式化逻辑（GEN-1）
 */
export function formatCents(priceCents: number): string {
  const yuan = Math.floor(priceCents / 100);
  const cents = priceCents % 100;
  return `¥${yuan}.${cents.toString().padStart(2, '0')}`;
}
