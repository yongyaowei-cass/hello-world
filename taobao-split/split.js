export function computeSplit({ lineItems, friendUnits, finalTotal }) {
  const currencies = new Set(lineItems.map((item) => item.currency));
  if (currencies.size > 1) {
    return { error: 'mixed-item-currency' };
  }

  let friendValue = 0;
  let totalValue = 0;

  for (let i = 0; i < lineItems.length; i += 1) {
    const item = lineItems[i];
    const units = friendUnits[i] ?? 0;

    if (units < 0 || units > item.qty) {
      return { error: 'friend-units-out-of-range' };
    }

    friendValue += units * item.unitPrice;
    totalValue += item.qty * item.unitPrice;
  }

  if (totalValue === 0) {
    return { error: 'zero-total-value' };
  }

  const friendShare = friendValue / totalValue;
  const friendOwes = friendShare * finalTotal.amount;

  return { friendShare, friendOwes, currency: finalTotal.currency };
}
