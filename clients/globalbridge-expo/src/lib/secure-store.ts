import * as SecureStore from 'expo-secure-store';

const DEFAULT_OPTIONS: SecureStore.SecureStoreOptions = {
  keychainAccessible: SecureStore.SECURE_STORE_KEYCHAIN_ACCESSIBLE.ALWAYS_THIS_DEVICE_ONLY,
};

export async function setSecureItem<T>(
  key: string,
  value: T,
  options: SecureStore.SecureStoreOptions = DEFAULT_OPTIONS,
) {
  const payload = JSON.stringify(value);
  await SecureStore.setItemAsync(key, payload, options);
}

export async function getSecureItem<T>(
  key: string,
): Promise<T | null> {
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
