export function renderLineItems(container, lineItems, friendUnits, onChange, onRemove) {
  container.innerHTML = '';

  lineItems.forEach((item, index) => {
    const row = document.createElement('div');
    row.className = 'line-item';

    const nameInput = document.createElement('input');
    nameInput.type = 'text';
    nameInput.placeholder = 'Item name';
    nameInput.className = 'item-name-input';
    nameInput.value = item.name;

    const priceInput = document.createElement('input');
    priceInput.type = 'number';
    priceInput.step = '0.01';
    priceInput.min = '0';
    priceInput.placeholder = 'Unit price';
    priceInput.className = 'unit-price-input';
    priceInput.value = String(item.unitPrice);

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

    const removeBtn = document.createElement('button');
    removeBtn.type = 'button';
    removeBtn.className = 'remove-item-btn';
    removeBtn.textContent = 'Remove';

    nameInput.addEventListener('input', () => {
      item.name = nameInput.value;
      onChange();
    });

    priceInput.addEventListener('input', () => {
      item.unitPrice = Number(priceInput.value) || 0;
      onChange();
    });

    qtyInput.addEventListener('input', () => {
      item.qty = Number(qtyInput.value) || 0;
      friendInput.max = String(item.qty);
      onChange();
    });

    friendInput.addEventListener('input', () => {
      friendUnits[index] = Number(friendInput.value) || 0;
      onChange();
    });

    removeBtn.addEventListener('click', () => {
      onRemove(index);
    });

    row.append(nameInput, priceInput, qtyInput, friendLabel, friendInput, removeBtn);
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
      return 'Total item value is zero — check the unit prices and quantities.';
    default:
      return 'Could not compute split.';
  }
}
