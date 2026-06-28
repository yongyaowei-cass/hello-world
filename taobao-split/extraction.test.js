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
