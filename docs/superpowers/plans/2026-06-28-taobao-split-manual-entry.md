# Taobao Split Manual Entry Pivot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the screenshot/vision-API input in the Taobao Split app with manual entry, so the tool requires no Claude API key and costs nothing to run.

**Architecture:** Delete the vision-extraction and API-key-storage modules entirely. Rewrite the static page so the user types line items directly into dynamic rows (with an "Add item" / per-row "Remove" control), enters one currency for the whole order, and enters the final amount paid plus its currency. The existing pure split-calculation module (`split.js`) is untouched — it already accepts exactly this shape of data.

**Tech Stack:** Vanilla HTML/CSS/JS (ES modules), Node's built-in test runner (`node --test`), no build step, no network calls.

## Global Constraints

- No Claude API, no API key, and no network calls anywhere in the app after this pivot.
- One currency field for the whole order, applied to every line item — there is no per-item currency input.
- `taobao-split/split.js` and `taobao-split/split.test.js` must remain unmodified by this plan; the pivot only changes how data enters the app, not the split math.
- No build step, no framework — plain ES modules, same as the existing codebase.
- Element ids and CSS class names used by JS must exactly match those defined in the HTML/CSS task — nothing else catches a mismatch.
- Test command (verified working on this system): `node --test taobao-split/*.test.js` (a bare `node --test taobao-split/` does not work — do not use that form).

---

### Task 1: Manual-entry page markup

**Files:**
- Modify: `taobao-split/index.html` (full rewrite of the `<body>` contents)
- Modify: `taobao-split/styles.css` (full rewrite)

**Interfaces:**
- Consumes: nothing.
- Produces: a static DOM with these exact element ids, which Task 2 and Task 3 will query:
  - `#order-currency-input` (text input, default value `CNY`)
  - `#line-items` (empty container, rows injected by Task 2's `render.js`)
  - `#add-item-btn` (button)
  - `#final-total-input` (number input)
  - `#final-total-currency-input` (text input)
  - `#status` (paragraph, used only for "Summary copied." feedback now)
  - `#result` (section)
  - `#copy-btn` (button, `hidden` by default)
- Produces these exact CSS class names, which Task 2's `render.js` will assign to elements it creates: `.line-item`, `.item-name-input`, `.unit-price-input`, `.qty-input`, `.friend-units-input`, `.remove-item-btn`.
- The old ids `api-key-input`, `save-key-btn`, `file-input`, `final-total-currency` (the old `<span>`) and the old "key-section"/"upload-section" sections are removed entirely — they no longer exist anywhere in the app after this pivot.

- [ ] **Step 1: Rewrite the HTML**

Replace the entire contents of `taobao-split/index.html` with:

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

    <section id="currency-section">
      <label for="order-currency-input">Item currency</label>
      <input id="order-currency-input" type="text" value="CNY" />
    </section>

    <section id="line-items"></section>

    <button id="add-item-btn" type="button">Add item</button>

    <section id="total-section">
      <label for="final-total-input">Amount paid</label>
      <input id="final-total-input" type="number" step="0.01" />
      <label for="final-total-currency-input">Paid currency</label>
      <input id="final-total-currency-input" type="text" placeholder="e.g. SGD" />
    </section>

    <p id="status" role="status"></p>

    <section id="result"></section>

    <button id="copy-btn" type="button" hidden>Copy summary</button>
  </main>
  <script type="module" src="app.js"></script>
</body>
</html>
```

- [ ] **Step 2: Rewrite the styles**

Replace the entire contents of `taobao-split/styles.css` with:

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

input[type='text'],
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

.line-item .item-name-input {
  flex: 1 1 8rem;
  width: auto;
}

.line-item .unit-price-input,
.line-item .qty-input,
.line-item .friend-units-input {
  width: 4rem;
}

.line-item .remove-item-btn {
  margin-top: 0;
  background: #fee;
  border: 1px solid #b00;
  color: #b00;
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

- [ ] **Step 3: Verify the markup is well-formed**

Run: `node --check-syntax` is not applicable to HTML/CSS; instead start a static server from inside `taobao-split/` (`npx --yes serve .` or `python -m http.server 8000`) and `curl` the served `index.html`.
Expected: 200 response; the response body contains `<title>Taobao Split</title>` and every id listed in this task's "Produces" section above (grep for each id string in the curl output). The page will show a 404 in the browser console for `app.js` (it still references the old `app.js`, which Task 3 has not yet rewritten) — that is expected at this point, not a defect for this task.

- [ ] **Step 4: Commit**

```bash
git add taobao-split/index.html taobao-split/styles.css
git commit -m "feat: rewrite Taobao split page markup for manual entry"
```

---

### Task 2: Editable row rendering

**Files:**
- Modify: `taobao-split/render.js` (full rewrite of `renderLineItems`; `renderResult` and `describeError` are unchanged — leave them exactly as they are)

**Interfaces:**
- Consumes: the element ids and CSS class names from Task 1's `index.html`/`styles.css`.
- Produces: `renderLineItems(container, lineItems, friendUnits, onChange, onRemove)` where:
  - `container`: a DOM element (Task 3 will pass `document.getElementById('line-items')`)
  - `lineItems`: `Array<{ name: string, unitPrice: number, currency: string, qty: number }>` — mutated in place as the user edits name/price/qty fields
  - `friendUnits`: `Array<number>`, parallel to `lineItems` — mutated in place as the user edits the friend's-units field
  - `onChange: () => void` — called after any field edit (name, price, qty, or friend units)
  - `onRemove: (index: number) => void` — called when a row's Remove button is clicked, passing that row's index
  - (unchanged) `renderResult(container, result, currency)` and the internal `describeError(error)` helper, exactly as they exist today — do not modify them in this task.

- [ ] **Step 1: Rewrite `renderLineItems`**

Replace the `renderLineItems` function in `taobao-split/render.js` (keep `renderResult` and `describeError` below it exactly as they are) with:

```js
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
```

The rest of `taobao-split/render.js` (the `renderResult` function and the `describeError` helper) stays exactly as it is today — do not change it.

- [ ] **Step 2: Verify syntax and cross-reference against Task 1's markup**

Run: `node --check taobao-split/render.js`
Expected: no output (syntax is valid). Note `node --check` rejects top-level `import`/`export` in some Node versions when the file isn't recognized as a module — if it errors specifically on `export`/`import` syntax rather than a real syntax mistake, that is expected for this file and not a defect; read the file by eye to confirm there are no other syntax errors instead.

Then re-read `taobao-split/render.js` against `taobao-split/index.html` and `taobao-split/styles.css` from Task 1: confirm every CSS class assigned in this file (`line-item`, `item-name-input`, `unit-price-input`, `qty-input`, `friend-units-input`, `remove-item-btn`) appears as a selector in `styles.css`, with no typos.

- [ ] **Step 3: Commit**

```bash
git add taobao-split/render.js
git commit -m "feat: render editable item rows for manual entry"
```

---

### Task 3: App wiring for manual entry, and removal of vision/API-key modules

**Files:**
- Modify: `taobao-split/app.js` (full rewrite)
- Delete: `taobao-split/extraction.js`
- Delete: `taobao-split/extraction.test.js`
- Delete: `taobao-split/apiKey.js`
- Delete: `taobao-split/apiKey.test.js`

**Interfaces:**
- Consumes:
  - `computeSplit` from `taobao-split/split.js` (unchanged: `computeSplit({ lineItems, friendUnits, finalTotal })` → `{ friendShare, friendOwes, currency }` or `{ error }`)
  - `renderLineItems(container, lineItems, friendUnits, onChange, onRemove)` and `renderResult(container, result, currency)` from `taobao-split/render.js` (Task 2)
  - The exact element ids from `taobao-split/index.html` (Task 1)
- Produces: nothing consumed by any later task — this is the last code-wiring task. After this task, `taobao-split/` contains no reference to `extraction.js`, `apiKey.js`, `callVisionApi`, `getStoredApiKey`, `setStoredApiKey`, `window.localStorage`, or `fetch` anywhere.

- [ ] **Step 1: Delete the vision and API-key modules**

```bash
git rm taobao-split/extraction.js taobao-split/extraction.test.js taobao-split/apiKey.js taobao-split/apiKey.test.js
```

- [ ] **Step 2: Rewrite app.js**

Replace the entire contents of `taobao-split/app.js` with:

```js
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
```

- [ ] **Step 3: Confirm the remaining test suite passes**

Run: `node --test taobao-split/*.test.js`
Expected: PASS, 6 tests (only `split.test.js` remains after deleting `extraction.test.js` and `apiKey.test.js`).

- [ ] **Step 4: Manually verify the full flow in a browser**

Run: `npx --yes serve taobao-split` (or `python -m http.server 8000` from inside `taobao-split/`), then open the served URL in a browser.

1. Page loads with one blank item row, "Item currency" pre-filled with `CNY`, `#copy-btn` hidden.
2. Click "Add item" → a second blank row appears.
3. In row 1, type name `OP07 SR`, unit price `49.16`, quantity `4`, friend units `0`.
4. In row 2, type name `OP16 SR`, unit price `78.65`, quantity `8`, friend units `4`.
5. Set "Amount paid" to `180.65` and "Paid currency" to `SGD`.
6. `#result` updates live to show approximately "Friend's share: 38.1% — owes 68.82 SGD" and `#copy-btn` becomes visible.
7. Click "Copy summary" → `#status` shows "Summary copied."; paste somewhere to confirm the clipboard text reads like "Friend owes 68.82 SGD (38.1% of order)".
8. Click "Remove" on row 1 → it disappears, and `#result` recomputes (now friend owns all remaining value, so friend's share becomes 100%).
9. Remove the remaining row too → `#result` shows the "Total item value is zero" error message, and `#copy-btn` hides again.

Expected: all nine checks behave as described, with no console errors (confirm `app.js` and `render.js` load without a 404 now, unlike Task 1's transient state).

- [ ] **Step 5: Commit**

```bash
git add taobao-split/app.js
git commit -m "feat: wire up manual entry and remove vision/API-key modules"
```

---

### Task 4: Update README for manual entry

**Files:**
- Modify: `taobao-split/README.md` (full rewrite)

**Interfaces:**
- None — documentation only.

- [ ] **Step 1: Rewrite the README**

Replace the entire contents of `taobao-split/README.md` with:

```markdown
# Taobao Split

A single-page tool for splitting a joint Taobao order between you and one
friend, proportional to the value of the items each of you owns. You type in
the order's line items and the final amount paid; it computes the friend's
share of the actual amount paid (shipping, fees, GST, and discounts included
automatically — see the design doc for why this works). No API key, no
network calls, no cost.

## Usage

1. Open the page (locally or deployed).
2. Set the "Item currency" field to match your order (e.g. "CNY").
3. For each item in the order, fill in its name, unit price, and quantity.
   Click "Add item" for more rows, or "Remove" to delete a row.
4. For each item, set how many units belong to your friend.
5. Fill in the amount actually paid and its currency.
6. Read the computed split, or tap "Copy summary" to paste it to your friend.

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
git commit -m "docs: update README for manual entry usage"
```
