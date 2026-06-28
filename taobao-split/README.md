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
