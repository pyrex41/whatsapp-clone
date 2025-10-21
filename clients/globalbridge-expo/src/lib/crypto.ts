import * as Crypto from 'expo-crypto';

const SALT_BYTES = 16;

export async function hashPin(pin: string, salt?: string) {
  const resolvedSalt = salt ?? (await generateSalt());
  const digest = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    `${pin}:${resolvedSalt}`,
  );

  return { hash: digest, salt: resolvedSalt };
}

export async function generateSalt() {
  const bytes = await Crypto.getRandomBytesAsync(SALT_BYTES);
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}
