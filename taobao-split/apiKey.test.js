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
