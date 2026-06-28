export function renderLineItems(container, lineItems, friendUnits, onChange) {
  container.innerHTML = '';

  lineItems.forEach((item, index) => {
    const row = document.createElement('div');
    row.className = 'line-item';

    const label = document.createElement('span');
    // item.name comes from untrusted LLM-extracted image content — keep this
    // as textContent (never innerHTML/template interpolation) to avoid XSS.
    label.textContent = `${item.name} · ${item.unitPrice} ${item.currency} ×`;

    const qtyInput = document.createElement('input');
    qtyInput.type = 'number';
    qtyInput.min = '0';
    qtyInput.className = 'qty-input';
    qtyInput.value = String(item.qty);

    const friendLabel = document.createElement('span');
    friendLabel.textContent = 'friend units:';

    const friendInput = document.createElement('input');
    friendInput.type = 'number';
    friendInput.min = '0';
    friendInput.max = String(item.qty);
    friendInput.className = 'friend-units-input';
    friendInput.value = String(friendUnits[index] ?? 0);

    qtyInput.addEventListener('input', () => {
      item.qty = Number(qtyInput.value) || 0;
      friendInput.max = String(item.qty);
      onChange();
    });

    friendInput.addEventListener('input', () => {
      friendUnits[index] = Number(friendInput.value) || 0;
      onChange();
    });

    row.append(label, qtyInput, friendLabel, friendInput);
    container.appendChild(row);
  });
}

export function renderResult(container, result, currency) {
  container.innerHTML = '';

  if (!result || result.error) {
    container.textContent = result?.error ? describeError(result.error) : '';
    return;
  }

  const pct = (result.friendShare * 100).toFixed(1);
  const owed = result.friendOwes.toFixed(2);
  container.textContent = `Friend's share: ${pct}% — owes ${owed} ${currency}`;
}

function describeError(error) {
  switch (error) {
    case 'mixed-item-currency':
      return 'Line items use different currencies — cannot compute a single ratio.';
    case 'friend-units-out-of-range':
      return "Friend's units cannot exceed the item quantity.";
    case 'zero-total-value':
      return 'Total item value is zero — check the extracted prices.';
    default:
      return 'Could not compute split.';
  }
}
