import * as SecureStore from 'expo-secure-store';

export async function setSecureItem<T>(key: string, value: T, options?: SecureStore.SecureStoreOptions) {
  const payload = JSON.stringify(value);
  await SecureStore.setItemAsync(key, payload, options);
}

export async function getSecureItem<T>(key: string): Promise<T | null> {
  const raw = await SecureStore.getItemAsync(key);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch (error) {
    console.warn(`[secure-store] Failed to parse value for ${key}`, error);
    return null;
  }
}

export async function deleteSecureItem(key: string) {
  await SecureStore.deleteItemAsync(key);
}
