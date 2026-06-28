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
