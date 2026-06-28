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
