import { computeSplit } from './split.js';
import { callVisionApi } from './extraction.js';
import { getStoredApiKey, setStoredApiKey } from './apiKey.js';
import { renderLineItems, renderResult } from './render.js';

const keyInput = document.getElementById('api-key-input');
const saveKeyBtn = document.getElementById('save-key-btn');
const fileInput = document.getElementById('file-input');
const status = document.getElementById('status');
const lineItemsSection = document.getElementById('line-items');
const totalInput = document.getElementById('final-total-input');
const totalCurrency = document.getElementById('final-total-currency');
const resultSection = document.getElementById('result');
const copyBtn = document.getElementById('copy-btn');

let lineItems = [];
let friendUnits = [];
let finalTotal = null;

const existingKey = getStoredApiKey(window.localStorage);
if (existingKey) {
  keyInput.value = existingKey;
}

saveKeyBtn.addEventListener('click', () => {
  setStoredApiKey(keyInput.value.trim(), window.localStorage);
  status.textContent = 'API key saved.';
});

fileInput.addEventListener('change', async () => {
  const file = fileInput.files[0];
  if (!file) return;

  const apiKey = getStoredApiKey(window.localStorage);
  if (!apiKey) {
    status.textContent = 'Save your API key first.';
    return;
  }

  status.textContent = 'Reading screenshot...';

  const { base64, mediaType } = await fileToBase64(file);
  const extracted = await callVisionApi({ imageBase64: base64, mediaType, apiKey });

  if (extracted.error) {
    status.textContent = "Couldn't read this screenshot, try a clearer crop.";
    return;
  }

  status.textContent = '';
  lineItems = extracted.lineItems;
  friendUnits = lineItems.map(() => 0);
  finalTotal = extracted.finalTotal;

  totalInput.value = String(finalTotal.amount);
  totalCurrency.textContent = finalTotal.currency;

  renderLineItems(lineItemsSection, lineItems, friendUnits, recompute);
  recompute();
});

totalInput.addEventListener('input', () => {
  if (!finalTotal) return;
  finalTotal = { ...finalTotal, amount: Number(totalInput.value) || 0 };
  recompute();
});

function recompute() {
  if (!finalTotal || lineItems.length === 0) return;

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

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const [, base64] = String(reader.result).split(',');
      resolve({ base64, mediaType: file.type });
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}
