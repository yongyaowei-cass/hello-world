# Taobao Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-page, phone-friendly web app that reads a Taobao order screenshot via Claude's vision API and computes how much a friend owes for the items they share, proportional to item value.

**Architecture:** A static page (`taobao-split/index.html` + vanilla JS/CSS, no build step, no framework) calls the Claude Messages API directly from the browser with a user-supplied API key stored in `localStorage`. Vision extraction returns structured JSON (line items + final paid total); a pure calculation module turns that plus user-entered "friend's units" into a split. DOM rendering wires the two together.

**Tech Stack:** Vanilla HTML/CSS/JS (ES modules), Node's built-in test runner (`node --test`) for pure-function unit tests, Claude API (`claude-opus-4-8`, vision + direct browser access header), static hosting (e.g. GitHub Pages).

## Global Constraints

- Exactly two people per order: the user and one friend. No support for more.
- One order per session. No accounts, no history, no persistence beyond the API key.
- Input is a screenshot only (no manual order entry, no OCR fallback).
- Vision extraction uses model `claude-opus-4-8`.
- All line-item prices are assumed to share one currency; if extraction ever returns mixed currencies across line items, the app must show an error rather than silently convert.
- No build step, no framework — plain ES modules served as static files.
- The Claude API key lives in browser `localStorage`. This is acceptable only because this is a single-user personal tool, not a shared/public deployment.
- Shared costs (shipping, fees, GST, rebates) are never itemized — the friend's share is always computed as their fraction of item value, applied to the actual final amount paid.

---

### Task 1: Split calculation core

**Files:**
- Create: `taobao-split/package.json`
- Create: `taobao-split/split.js`
- Test: `taobao-split/split.test.js`

**Interfaces:**
- Produces: `computeSplit({ lineItems, friendUnits, finalTotal })` where:
  - `lineItems`: `Array<{ name: string, unitPrice: number, currency: string, qty: number }>`
  - `friendUnits`: `Array<number>`, parallel to `lineItems`, each `0 <= friendUnits[i] <= lineItems[i].qty`
  - `finalTotal`: `{ amount: number, currency: string }`
  - Returns either `{ friendShare: number, friendOwes: number, currency: string }` or `{ error: 'mixed-item-currency' | 'friend-units-out-of-range' | 'zero-total-value' }`

- [ ] **Step 1: Create the package scaffold**

```json
{
  "name": "taobao-split",
  "private": true,
  "type": "module"
}
```

Write this to `taobao-split/package.json`. The `"type": "module"` lets Node treat all `.js` files in this folder as ES modules, and lets `node --test` discover `*.test.js` files here.

- [ ] **Step 2: Write the failing tests**

Create `taobao-split/split.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computeSplit } from './split.js';

test('worked example from the spec: partial split on one item', () => {
  const lineItems = [
    { name: 'OP07 SR', unitPrice: 49.16, currency: 'CNY', qty: 4 },
    { name: 'OP16 SR', unitPrice: 78.65, currency: 'CNY', qty: 8 },
  ];
  const friendUnits = [0, 4];
  const finalTotal = { amount: 180.65, currency: 'SGD' };

  const result = computeSplit({ lineItems, friendUnits, finalTotal });

  assert.equal(result.error, undefined);
  assert.ok(Math.abs(result.friendShare - 0.381) < 0.001);
  assert.ok(Math.abs(result.friendOwes - 68.83) < 0.01);
  assert.equal(result.currency, 'SGD');
});

test('friend owns 100% of a single item', () => {
  const lineItems = [{ name: 'Item', unitPrice: 10, currency: 'CNY', qty: 2 }];
  const friendUnits = [2];
  const finalTotal = { amount: 20, currency: 'SGD' };

  const result = computeSplit({ lineItems, friendUnits, finalTotal });

  assert.equal(result.friendShare, 1);
  assert.equal(result.friendOwes, 20);
});

test('even 50/50 split across two identical items', () => {
  const lineItems = [
    { name: 'Item A', unitPrice: 10, currency: 'CNY', qty: 1 },
    { name: 'Item B', unitPrice: 10, currency: 'CNY', qty: 1 },
  ];
  const friendUnits = [1, 0];
  const finalTotal = { amount: 30, currency: 'SGD' };

  const result = computeSplit({ lineItems, friendUnits, finalTotal });

  assert.equal(result.friendShare, 0.5);
  assert.equal(result.friendOwes, 15);
});

test('friend owns zero units', () => {
  const lineItems = [{ name: 'Item', unitPrice: 10, currency: 'CNY', qty: 4 }];
  const friendUnits = [0];
  const finalTotal = { amount: 40, currency: 'SGD' };

  const result = computeSplit({ lineItems, friendUnits, finalTotal });

  assert.equal(result.friendShare, 0);
  assert.equal(result.friendOwes, 0);
});

test('mixed currencies across line items is an error', () => {
  const lineItems = [
    { name: 'Item A', unitPrice: 10, currency: 'CNY', qty: 1 },
    { name: 'Item B', unitPrice: 10, currency: 'SGD', qty: 1 },
  ];
  const friendUnits = [0, 1];
  const finalTotal = { amount: 20, currency: 'SGD' };

  const result = computeSplit({ lineItems, friendUnits, finalTotal });

  assert.equal(result.error, 'mixed-item-currency');
});

test('friend units exceeding quantity is an error', () => {
  const lineItems = [{ name: 'Item', unitPrice: 10, currency: 'CNY', qty: 2 }];
  const friendUnits = [3];
  const finalTotal = { amount: 20, currency: 'SGD' };

  const result = computeSplit({ lineItems, friendUnits, finalTotal });

  assert.equal(result.error, 'friend-units-out-of-range');
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `node --test taobao-split/*.test.js`
Expected: FAIL — `split.js` does not exist yet (`Cannot find module './split.js'`).

- [ ] **Step 4: Write the implementation**

Create `taobao-split/split.js`:

```js
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `node --test taobao-split/*.test.js`
Expected: PASS — all 6 tests green.

- [ ] **Step 6: Commit**

```bash
git add taobao-split/package.json taobao-split/split.js taobao-split/split.test.js
git commit -m "feat: add split calculation core for Taobao split tool"
```

---

### Task 2: Vision extraction response parsing

**Files:**
- Create: `taobao-split/extraction.js`
- Test: `taobao-split/extraction.test.js`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `buildExtractionPrompt(): string`
  - `parseExtractionResponse(rawText: string)` → either `{ lineItems, finalTotal, rawCostsSeen }` (same `lineItems`/`finalTotal` shapes as Task 1's `computeSplit` expects) or `{ error: 'invalid-json' | 'missing-total' }`
  - `callVisionApi({ imageBase64, mediaType, apiKey }): Promise<...>` — same return shape as `parseExtractionResponse`, plus `{ error: 'api-request-failed' }` on a failed HTTP call. This function makes a real network call and is exercised manually in Task 5, not by unit tests.

- [ ] **Step 1: Write the failing tests**

Create `taobao-split/extraction.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseExtractionResponse } from './extraction.js';

test('parses a well-formed extraction response', () => {
  const raw = JSON.stringify({
    lineItems: [
      { name: 'OP07 SR', unitPrice: 49.16, currency: 'CNY', qty: 4 },
      { name: 'OP16 SR', unitPrice: 78.65, currency: 'CNY', qty: 8 },
    ],
    finalTotal: { amount: 180.65, currency: 'SGD' },
    rawCostsSeen: ['海外运费 ¥5.46'],
  });

  const result = parseExtractionResponse(raw);

  assert.equal(result.error, undefined);
  assert.equal(result.lineItems.length, 2);
  assert.equal(result.finalTotal.amount, 180.65);
  assert.deepEqual(result.rawCostsSeen, ['海外运费 ¥5.46']);
});

test('defaults rawCostsSeen to an empty array when absent', () => {
  const raw = JSON.stringify({
    lineItems: [{ name: 'Item', unitPrice: 10, currency: 'CNY', qty: 1 }],
    finalTotal: { amount: 10, currency: 'SGD' },
  });

  const result = parseExtractionResponse(raw);

  assert.deepEqual(result.rawCostsSeen, []);
});

test('invalid JSON text is an error', () => {
  const result = parseExtractionResponse('not json at all');
  assert.equal(result.error, 'invalid-json');
});

test('empty lineItems array is an error', () => {
  const raw = JSON.stringify({ lineItems: [], finalTotal: { amount: 10, currency: 'SGD' } });
  const result = parseExtractionResponse(raw);
  assert.equal(result.error, 'invalid-json');
});

test('a line item missing a required field is an error', () => {
  const raw = JSON.stringify({
    lineItems: [{ name: 'Item', unitPrice: 10, qty: 1 }],
    finalTotal: { amount: 10, currency: 'SGD' },
  });
  const result = parseExtractionResponse(raw);
  assert.equal(result.error, 'invalid-json');
});

test('missing finalTotal is an error', () => {
  const raw = JSON.stringify({
    lineItems: [{ name: 'Item', unitPrice: 10, currency: 'CNY', qty: 1 }],
  });
  const result = parseExtractionResponse(raw);
  assert.equal(result.error, 'missing-total');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test taobao-split/*.test.js`
Expected: FAIL — `extraction.js` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `taobao-split/extraction.js`:

```js
export function buildExtractionPrompt() {
  return [
    'You are reading a screenshot of a Taobao order page.',
    "Extract each product line item's displayed unit price, its currency, and its quantity.",
    'Also extract the final amount actually paid (labeled something like 实付款).',
    'Respond with ONLY valid JSON, no markdown fences, no commentary, matching exactly this shape:',
    '{"lineItems":[{"name":string,"unitPrice":number,"currency":"CNY"|"SGD","qty":number}],"finalTotal":{"amount":number,"currency":string},"rawCostsSeen":[string]}',
  ].join(' ');
}

export function parseExtractionResponse(rawText) {
  let data;
  try {
    data = JSON.parse(rawText);
  } catch {
    return { error: 'invalid-json' };
  }

  if (!Array.isArray(data.lineItems) || data.lineItems.length === 0) {
    return { error: 'invalid-json' };
  }

  for (const item of data.lineItems) {
    if (
      typeof item.name !== 'string' ||
      typeof item.unitPrice !== 'number' ||
      typeof item.currency !== 'string' ||
      typeof item.qty !== 'number'
    ) {
      return { error: 'invalid-json' };
    }
  }

  if (
    !data.finalTotal ||
    typeof data.finalTotal.amount !== 'number' ||
    typeof data.finalTotal.currency !== 'string'
  ) {
    return { error: 'missing-total' };
  }

  return {
    lineItems: data.lineItems,
    finalTotal: data.finalTotal,
    rawCostsSeen: Array.isArray(data.rawCostsSeen) ? data.rawCostsSeen : [],
  };
}

export async function callVisionApi({ imageBase64, mediaType, apiKey }) {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true',
    },
    body: JSON.stringify({
      model: 'claude-opus-4-8',
      max_tokens: 1024,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageBase64 } },
            { type: 'text', text: buildExtractionPrompt() },
          ],
        },
      ],
    }),
  });

  if (!response.ok) {
    return { error: 'api-request-failed' };
  }

  const data = await response.json();
  const textBlock = (data.content || []).find((block) => block.type === 'text');

  if (!textBlock) {
    return { error: 'invalid-json' };
  }

  return parseExtractionResponse(textBlock.text);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test taobao-split/*.test.js`
Expected: PASS — all tests from Task 1 and Task 2 green (12 total).

- [ ] **Step 5: Commit**

```bash
git add taobao-split/extraction.js taobao-split/extraction.test.js
git commit -m "feat: add vision extraction prompt and response parsing"
```

---

### Task 3: API key storage

**Files:**
- Create: `taobao-split/apiKey.js`
- Test: `taobao-split/apiKey.test.js`

**Interfaces:**
- Consumes: nothing from Tasks 1–2.
- Produces:
  - `getStoredApiKey(storage): string | null`
  - `setStoredApiKey(key: string, storage): void`
  - `clearStoredApiKey(storage): void`
  - `storage` is any object implementing `getItem(key)`, `setItem(key, value)`, `removeItem(key)` (matching the `Storage`/`localStorage` interface), passed in by the caller so this module never touches `window` directly.

- [ ] **Step 1: Write the failing tests**

Create `taobao-split/apiKey.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { getStoredApiKey, setStoredApiKey, clearStoredApiKey } from './apiKey.js';

function createMockStorage() {
  const map = new Map();
  return {
    getItem: (key) => (map.has(key) ? map.get(key) : null),
    setItem: (key, value) => map.set(key, value),
    removeItem: (key) => map.delete(key),
  };
}

test('returns null when no key has been stored', () => {
  const storage = createMockStorage();
  assert.equal(getStoredApiKey(storage), null);
});

test('stores and retrieves a key', () => {
  const storage = createMockStorage();
  setStoredApiKey('sk-ant-test123', storage);
  assert.equal(getStoredApiKey(storage), 'sk-ant-test123');
});

test('clears a stored key', () => {
  const storage = createMockStorage();
  setStoredApiKey('sk-ant-test123', storage);
  clearStoredApiKey(storage);
  assert.equal(getStoredApiKey(storage), null);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test taobao-split/*.test.js`
Expected: FAIL — `apiKey.js` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `taobao-split/apiKey.js`:

```js
const STORAGE_KEY = 'taobao-split-api-key';

export function getStoredApiKey(storage) {
  return storage.getItem(STORAGE_KEY);
}

export function setStoredApiKey(key, storage) {
  storage.setItem(STORAGE_KEY, key);
}

export function clearStoredApiKey(storage) {
  storage.removeItem(STORAGE_KEY);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test taobao-split/*.test.js`
Expected: PASS — all tests from Tasks 1–3 green (15 total).

- [ ] **Step 5: Commit**

```bash
git add taobao-split/apiKey.js taobao-split/apiKey.test.js
git commit -m "feat: add localStorage-backed API key storage helper"
```

---

### Task 4: Static page skeleton

**Files:**
- Create: `taobao-split/index.html`
- Create: `taobao-split/styles.css`

**Interfaces:**
- Produces: a static DOM with these exact element ids, which Task 5's `app.js` will query:
  - `#api-key-input`, `#save-key-btn`
  - `#file-input`
  - `#status`
  - `#line-items`
  - `#final-total-input`, `#final-total-currency`
  - `#result`
  - `#copy-btn`
- No JavaScript behavior yet — this task only produces markup and styling.

- [ ] **Step 1: Create the HTML skeleton**

Create `taobao-split/index.html`:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Taobao Split</title>
  <link rel="stylesheet" href="styles.css" />
</head>
<body>
  <main>
    <h1>Taobao Split</h1>

    <section id="key-section">
      <label for="api-key-input">Claude API key</label>
      <input id="api-key-input" type="password" placeholder="sk-ant-..." />
      <button id="save-key-btn" type="button">Save key</button>
    </section>

    <section id="upload-section">
      <label for="file-input">Order screenshot</label>
      <input id="file-input" type="file" accept="image/*" />
    </section>

    <p id="status" role="status"></p>

    <section id="line-items"></section>

    <section id="total-section">
      <label for="final-total-input">Amount paid</label>
      <input id="final-total-input" type="number" step="0.01" />
      <span id="final-total-currency"></span>
    </section>

    <section id="result"></section>

    <button id="copy-btn" type="button" hidden>Copy summary</button>
  </main>
  <script type="module" src="app.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create mobile-first styles**

Create `taobao-split/styles.css`:

```css
* {
  box-sizing: border-box;
}

body {
  font-family: system-ui, sans-serif;
  margin: 0;
  padding: 1rem;
  max-width: 480px;
  margin-inline: auto;
}

section {
  margin-bottom: 1.25rem;
}

label {
  display: block;
  font-size: 0.875rem;
  margin-bottom: 0.25rem;
}

input,
button {
  font-size: 1rem;
  padding: 0.5rem;
}

input[type='password'],
input[type='file'],
input[type='number'] {
  width: 100%;
}

button {
  margin-top: 0.5rem;
}

.line-item {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 0;
  border-bottom: 1px solid #ddd;
}

.line-item .qty-input,
.line-item .friend-units-input {
  width: 4rem;
}

#status {
  color: #b00;
  min-height: 1.25rem;
}

#result {
  font-weight: bold;
  font-size: 1.1rem;
}
```

- [ ] **Step 3: Verify the skeleton renders**

Run: `npx --yes serve taobao-split` (or `python -m http.server 8000` from inside `taobao-split/`), then open the served URL in a browser.
Expected: page shows the title, an API key field with a Save button, a file picker, an empty status line, an "Amount paid" field, and a hidden "Copy summary" button. No JavaScript errors in the console (there is no `app.js` yet, so the browser will log a 404 for it — expected at this point, resolved in Task 5).

- [ ] **Step 4: Commit**

```bash
git add taobao-split/index.html taobao-split/styles.css
git commit -m "feat: add static page skeleton for Taobao split tool"
```

---

### Task 5: App wiring

**Files:**
- Create: `taobao-split/render.js`
- Create: `taobao-split/app.js`

**Interfaces:**
- Consumes:
  - `computeSplit` from `taobao-split/split.js` (Task 1)
  - `callVisionApi` from `taobao-split/extraction.js` (Task 2)
  - `getStoredApiKey`, `setStoredApiKey` from `taobao-split/apiKey.js` (Task 3)
  - The exact element ids defined in `taobao-split/index.html` (Task 4)
- Produces:
  - `renderLineItems(container, lineItems, friendUnits, onChange)` — builds one row per line item with an editable qty input and a friend's-units input; calls `onChange()` whenever either input changes.
  - `renderResult(container, result, currency)` — renders the computed split or a human-readable error message.

- [ ] **Step 1: Create the render module**

Create `taobao-split/render.js`:

```js
export function renderLineItems(container, lineItems, friendUnits, onChange) {
  container.innerHTML = '';

  lineItems.forEach((item, index) => {
    const row = document.createElement('div');
    row.className = 'line-item';

    const label = document.createElement('span');
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
```

- [ ] **Step 2: Create the app orchestration module**

Create `taobao-split/app.js`:

```js
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
```

- [ ] **Step 3: Run the unit test suite to confirm no regressions**

Run: `node --test taobao-split/*.test.js`
Expected: PASS — same 15 tests as after Task 3 (this task adds no new unit tests; DOM-dependent code is verified manually next).

- [ ] **Step 4: Manually verify the full flow in a browser**

Run: `npx --yes serve taobao-split` (or `python -m http.server 8000` from inside `taobao-split/`), then open the served URL in a browser.

1. Paste a real Claude API key into the key field and click "Save key" → status shows "API key saved."
2. Upload a Taobao order screenshot (e.g. the example order with OP07 SR ×4 and OP16 SR ×8, final total SGD 180.65) → status shows "Reading screenshot...", then clears; two line-item rows appear with their qty pre-filled; the "Amount paid" field shows 180.65 / SGD.
3. Set the second item's "friend units" to 4 → `#result` updates live to show approximately "Friend's share: 38.1% — owes 68.83 SGD".
4. Click "Copy summary" → status shows "Summary copied."; paste somewhere to confirm the clipboard text reads like "Friend owes 68.83 SGD (38.1% of order)".
5. Edit the "Amount paid" field to a different number → `#result` recomputes immediately.
6. Upload a screenshot of something that is clearly not a Taobao order (e.g. a random photo) → status shows "Couldn't read this screenshot, try a clearer crop."

Expected: all six checks behave as described. If extraction misreads a price or quantity, correct it via the qty input and confirm the result recomputes.

- [ ] **Step 5: Commit**

```bash
git add taobao-split/render.js taobao-split/app.js
git commit -m "feat: wire up Taobao split app end to end"
```

---

### Task 6: Usage and deployment README

**Files:**
- Create: `taobao-split/README.md`

**Interfaces:**
- None — this task only adds documentation. No code interfaces are produced or consumed.

- [ ] **Step 1: Write the README**

Create `taobao-split/README.md`:

```markdown
# Taobao Split

A single-page tool for splitting a joint Taobao order between you and one
friend, proportional to the value of the items each of you owns. Reads an
order screenshot with Claude's vision API, then computes the friend's share
of the actual amount paid (shipping, fees, GST, and discounts included
automatically — see the design doc for why this works).

## Usage

1. Open the page (locally or deployed).
2. Paste your Claude API key and click "Save key" (stored in your browser's
   `localStorage`; never sent anywhere except directly to Anthropic's API).
3. Upload a screenshot of the Taobao order.
4. For each line item, set how many units belong to your friend.
5. Read the computed split, or tap "Copy summary" to paste it to your friend.

This is a single-user personal tool: only use it on a device you control,
since your API key is stored unencrypted in the browser.

## Running locally

From inside this folder:

```
npx --yes serve .
```

or:

```
python -m http.server 8000
```

Then open the printed URL in a browser.

## Running tests

From the repository root:

```
node --test taobao-split/*.test.js
```

## Deploying

This is a static site with no build step. Any static host works, for
example GitHub Pages: push this folder to a repo and enable Pages on it, or
point Pages at a `taobao-split/` subfolder of an existing repo.
```

- [ ] **Step 2: Commit**

```bash
git add taobao-split/README.md
git commit -m "docs: add usage and deployment instructions for Taobao split tool"
```
