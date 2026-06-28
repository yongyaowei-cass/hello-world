import { computeSplit } from './split.js';
import { renderLineItems, renderResult } from './render.js';

const currencyInput = document.getElementById('order-currency-input');
const lineItemsSection = document.getElementById('line-items');
const addItemBtn = document.getElementById('add-item-btn');
const totalInput = document.getElementById('final-total-input');
const totalCurrencyInput = document.getElementById('final-total-currency-input');
const status = document.getElementById('status');
const resultSection = document.getElementById('result');
const copyBtn = document.getElementById('copy-btn');

let lineItems = [{ name: '', unitPrice: 0, currency: currencyInput.value, qty: 0 }];
let friendUnits = [0];

render();
recompute();

addItemBtn.addEventListener('click', () => {
  lineItems.push({ name: '', unitPrice: 0, currency: currencyInput.value, qty: 0 });
  friendUnits.push(0);
  render();
  recompute();
});

currencyInput.addEventListener('input', () => {
  lineItems.forEach((item) => {
    item.currency = currencyInput.value;
  });
  recompute();
});

totalInput.addEventListener('input', recompute);
totalCurrencyInput.addEventListener('input', recompute);

function render() {
  renderLineItems(lineItemsSection, lineItems, friendUnits, recompute, removeItem);
}

function removeItem(index) {
  lineItems.splice(index, 1);
  friendUnits.splice(index, 1);
  render();
  recompute();
}

function recompute() {
  const finalTotal = { amount: Number(totalInput.value) || 0, currency: totalCurrencyInput.value };
  const result = computeSplit({ lineItems, friendUnits, finalTotal });
  renderResult(resultSection, result, finalTotal.currency);

  copyBtn.hidden = Boolean(result.error);
  copyBtn.dataset.summary = result.error
    ? ''
    : `Friend owes ${result.friendOwes.toFixed(2)} ${finalTotal.currency} (${(result.friendShare * 100).toFixed(1)}% of order)`;
}

copyBtn.addEventListener('click', async () => {
  await navigator.clipboard.writeText(copyBtn.dataset.summary || '');
  status.textContent = 'Summary copied.';
});
