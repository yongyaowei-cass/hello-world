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
  assert.ok(Math.abs(result.friendOwes - 68.82) < 0.01);
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
