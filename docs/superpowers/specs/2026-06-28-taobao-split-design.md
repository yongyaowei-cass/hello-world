# Taobao Split — Design

## Problem

The user (Yao Wei) and a friend make joint Taobao purchases: a single order
contains items that belong wholly to one person, wholly to the other, or are
split between them by quantity. On top of the items, Taobao orders carry
shared costs (overseas shipping, payment fee, customs GST, coupons/rebates,
platform coin discounts) and the final amount paid is often in a different
currency (SGD) than the item prices (CNY). Manually working out who owes
what, correctly weighting the shared costs, is tedious and error-prone.

## Scope (MVP)

- Exactly **two people**: the user and one friend, per order.
- One order at a time. No history, no accounts, no persistence across
  sessions.
- Input is a **screenshot** of a Taobao order page (as shown to the user in
  the app/site).
- Out of scope: more than one friend, multiple orders in one session, saved
  history, login, non-Taobao receipts, offline/traditional OCR.

## Flow

1. User uploads an order screenshot to the page.
2. Page sends the image to the Claude vision API with a fixed extraction
   prompt and gets back structured JSON: line items (name, unit price,
   currency, quantity) and the final amount actually paid.
3. Page renders the extracted line items. For each item, the user sets how
   many of the units belong to the friend (0 up to the item's quantity), and
   can correct any misread price/quantity/total.
4. Page computes and displays the friend's share of the final total, plus a
   short summary the user can copy and send to the friend.

Refreshing the page discards the current order — no state is kept.

## Extraction contract

Vision call returns:

```json
{
  "lineItems": [
    { "name": "OP07 SR", "unitPrice": 49.16, "currency": "CNY", "qty": 4 },
    { "name": "OP16 SR", "unitPrice": 78.65, "currency": "CNY", "qty": 8 }
  ],
  "finalTotal": { "amount": 180.65, "currency": "SGD" },
  "rawCostsSeen": ["海外运费 ¥5.46", "支付手续费 SGD5.28", "报关GST ¥76.07", "红包 -¥14.22"]
}
```

- `unitPrice` is the **displayed per-unit price** on the order (already
  reflects any per-item discount).
- `rawCostsSeen` is informational only, shown to the user for a sanity
  check; it does not feed the calculation (see below).
- MVP assumes all `lineItems` share a single currency (CNY on Taobao). If the
  extraction ever returns mixed item currencies, the page flags this as an
  error rather than guessing a conversion.

## Split calculation

Shared costs (shipping, payment fee, GST, rebates, coin discounts) are
split proportionally to each person's share of item value — the approach the
user confirmed. Under that rule, the per-cost-line math collapses: each
person simply owes their share of the **final amount actually paid**.

```
friendValue = Σ (friendUnits_i × unitPrice_i)   over all line items i
totalValue  = Σ (qty_i        × unitPrice_i)   over all line items i
friendShare = friendValue / totalValue
friendOwes  = friendShare × finalTotal.amount   // in finalTotal.currency
```

This means the CNY/SGD currency mix and the individual shipping/GST/rebate
lines never need to be itemized or converted — the ratio derived from CNY
item prices is applied directly to the real amount paid, in whatever
currency that was.

Worked example (from the user's sample order):

- Friend's items: 4 × ¥78.65 = ¥314.60
- Total items: 4×¥49.16 + 8×¥78.65 = ¥825.84
- Friend's share: 314.60 / 825.84 ≈ 38.1%
- Friend owes: 0.381 × SGD 180.65 ≈ **SGD 68.83**

## Ownership & correction UI

For each line item, show `name · unitPrice · qty` with:

- An editable quantity field (vision may miscount).
- A stepper for "friend's units", bounded to `[0, qty]`.
- An editable final-total field, pre-filled from extraction.

The computed split updates live as these are edited.

## Error handling

- Extraction returns invalid/empty JSON → show a retry message ("couldn't
  read this screenshot, try a clearer crop").
- No API key stored yet → prompt the user to paste one before allowing
  upload.
- Friend's units cannot exceed the item's quantity (enforced by the
  stepper's max).
- Final total not detected → leave the field blank for manual entry instead
  of guessing.
- Mixed currencies across line items → show an error instead of computing a
  silently wrong ratio.

## Tech & deployment

- Single static page: `index.html` + vanilla JS/CSS, mobile-first layout. No
  build step, no framework.
- Browser calls the Claude API directly (using the browser-access header)
  with a user-supplied API key stored in `localStorage`.
- Hosted as a static site (e.g. GitHub Pages); opened on the user's phone.

## Testing

- Pure unit tests for the split calculation: the worked example above, plus
  edge cases (single owner takes 100%, even 50/50 split, friend owns 0
  units, mixed-currency line items → error).
- The vision extraction call is mocked in tests using fixed sample JSON
  responses, so tests do not depend on the live API.

## Open assumptions to revisit later

- Single shared-cost split rule (proportional to item value) covers this
  user's case; if costs ever need different rules per cost type, that would
  be a deliberate scope expansion, not an MVP requirement.
- API key living in browser `localStorage` is acceptable because this is a
  single-user personal tool, not a shared/public deployment.
