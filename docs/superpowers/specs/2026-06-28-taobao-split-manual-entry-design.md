# Taobao Split — Manual Entry Pivot — Design

## Why this supersedes the vision-based design

The original design ([2026-06-28-taobao-split-design.md](2026-06-28-taobao-split-design.md))
used Claude's vision API to read a Taobao order screenshot. The Claude API
is pay-per-use with no permanent free tier, and the user does not want to
pay anything to run this tool. This design replaces the screenshot/vision
input with manual entry: the user types the order details in directly.

The split-calculation core is unaffected and is not re-specified here — see
the original design's "Split calculation" section, which still applies
unchanged.

## What is removed

- `taobao-split/extraction.js` and `taobao-split/extraction.test.js` (vision
  prompt building, API call, response parsing) — deleted entirely.
- `taobao-split/apiKey.js` and `taobao-split/apiKey.test.js` (localStorage
  key storage) — deleted entirely, since there is no API key anymore.
- The "screenshot upload" and "save API key" UI sections.

## What is kept unchanged

- `taobao-split/split.js` and its tests — the pure `computeSplit({
  lineItems, friendUnits, finalTotal })` function and its 6 unit tests are
  untouched. It still accepts a `currency` field per line item; the new UI
  simply guarantees every item shares the same value (see below), so the
  function's mixed-currency error path becomes unreachable from the app but
  remains a valid defensive check, exercised directly by its own tests.

## New UI flow

1. The page loads with one blank item row already present: **name**,
   **unit price**, **quantity**, and a **friend's units** stepper (bounded
   `0..qty`), plus a **Remove** button for that row.
2. An **"Add item"** button appends another blank row, with the same
   fields.
3. One **order currency** field, entered once, applies to every item (e.g.
   "CNY"). There is no per-item currency field — this removes the
   mixed-currency UI case entirely, since the UI cannot produce it.
4. A **final total paid** field plus its own **currency** field (e.g.
   "180.65" / "SGD") — this can differ from the item currency, exactly as
   in the original design.
5. The result (friend's share %, amount owed, copyable summary) recomputes
   live on every change to any item field, the order currency, or the final
   total — same live-update behavior as the original design, just driven by
   typed input instead of extracted input.

## Data flow

`app.js` owns the `lineItems` array directly — there is no extraction step
that populates it from an API response. Each row's inputs write directly
into the corresponding `lineItems[i]` entry (with `currency` always set
from the single order-currency field, not per row). "Add item" pushes a new
blank entry (`{ name: '', unitPrice: 0, currency: <order currency>, qty: 0
}`) onto `lineItems` and a matching `0` onto `friendUnits`, then re-renders
the row list. "Remove" splices the corresponding entries out of both arrays
and re-renders. Every change handler calls the same `recompute()` →
`computeSplit()` → `renderResult()` path that already exists.

## Error handling

Most of the original error surface no longer applies, since there is no
extraction step:

- No "couldn't read this screenshot" case (no screenshot).
- No "missing API key" case (no API key).
- No mixed-currency case reachable from the UI (one currency field for the
  whole order).

What remains, unchanged from the original design and still enforced by
`computeSplit` itself:

- Friend's units exceeding an item's quantity → error, surfaced via the
  same `describeError` mapping already implemented in `render.js`.
- Zero total item value → error, same as before.

## File structure changes

- Delete: `taobao-split/extraction.js`, `taobao-split/extraction.test.js`,
  `taobao-split/apiKey.js`, `taobao-split/apiKey.test.js`.
- Rewrite: `taobao-split/index.html` (remove key/upload sections, add the
  dynamic item-entry list, "Add item" button, order-currency field, final
  total + its currency field).
- Rewrite: `taobao-split/styles.css` (drop now-unused selectors tied to the
  removed sections, add styles for the "Add item"/"Remove" buttons).
- Rewrite: `taobao-split/render.js` (render editable rows with name/unit
  price/qty/friend's-units inputs and a Remove button; no longer renders
  from extracted data, renders from the app-owned `lineItems` array
  directly).
- Rewrite: `taobao-split/app.js` (owns `lineItems`/`friendUnits` state from
  the start; wires Add/Remove buttons, the order-currency field, and the
  final-total fields; drops all API-key and vision-call wiring).
- Update: `taobao-split/README.md` (remove API key setup instructions,
  update usage steps to describe manual entry).

## Testing

`taobao-split/split.js`'s existing 6 unit tests are unaffected and remain
the project's only automated test coverage — this pivot does not add or
remove any pure, unit-testable logic. `render.js`/`app.js` remain manually
verified (DOM-dependent), per the original design's testing strategy; the
manual verification checklist shrinks since there is no API key or
screenshot step to exercise.

## Out of scope (unchanged from original design)

Multiple friends, more than one order/history, saved history, login,
non-Taobao receipts — all still out of scope, same as the original design.
