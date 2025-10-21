import { useCallback, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { useSession, useSessionActions } from '~/hooks/use-session';

export default function LockScreen() {
  const { unlockWithPin, unlockWithBiometrics, logout } = useSessionActions();
  const biometricsEnabled = useSession((state) => state.preferences.biometricsEnabled);
  const biometricsSupported = useSession((state) => state.biometricsSupported);

  const [pin, setPin] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const onUnlockWithPin = useCallback(async () => {
    if (submitting) return;
    setSubmitting(true);
    try {
      const ok = await unlockWithPin(pin);
      if (!ok) {
        Alert.alert('Incorrect PIN', 'Please try again.');
      }
    } finally {
      setSubmitting(false);
      setPin('');
    }
  }, [pin, submitting, unlockWithPin]);

  const onUnlockWithBiometrics = useCallback(async () => {
    const success = await unlockWithBiometrics();
    if (!success) {
      Alert.alert('Unable to unlock', 'Biometric authentication did not succeed.');
    }
  }, [unlockWithBiometrics]);

  return (
    <View style={styles.container}>
      <View>
        <Text style={styles.title}>Unlock GlobalBridge</Text>
        <Text style={styles.subtitle}>Your session is locked for security.</Text>
      </View>

      <View style={styles.section}>
        <Text style={styles.label}>Enter PIN</Text>
        <TextInput
          secureTextEntry
          keyboardType="number-pad"
          maxLength={6}
          value={pin}
          onChangeText={setPin}
          style={styles.input}
        />
        <Pressable
          accessibilityRole="button"
          style={({ pressed }) => [styles.button, pressed && styles.buttonPressed]}
          onPress={onUnlockWithPin}
          disabled={!pin || submitting}
        >
          <Text style={styles.buttonLabel}>{submitting ? 'Verifying…' : 'Unlock with PIN'}</Text>
        </Pressable>
      </View>

      {biometricsEnabled && biometricsSupported && (
        <View style={styles.section}>
          <Text style={styles.label}>Prefer biometrics?</Text>
          <Pressable
            accessibilityRole="button"
            style={({ pressed }) => [styles.secondaryButton, pressed && styles.buttonPressed]}
            onPress={onUnlockWithBiometrics}
          >
            <Text style={styles.secondaryButtonLabel}>Use Face ID / Touch ID</Text>
          </Pressable>
        </View>
      )}

      <Pressable
        accessibilityRole="button"
        style={({ pressed }) => [styles.linkButton, pressed && styles.buttonPressed]}
        onPress={logout}
      >
        <Text style={styles.linkText}>Sign out instead</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 24,
    backgroundColor: '#111827',
    justifyContent: 'center',
    gap: 24,
  },
  title: {
    fontSize: 28,
    fontWeight: '700',
    color: '#f9fafb',
  },
  subtitle: {
    fontSize: 16,
    color: '#d1d5db',
    marginTop: 4,
  },
  section: {
    gap: 12,
  },
  label: {
    fontSize: 14,
    color: '#9ca3af',
  },
  input: {
    borderWidth: 1,
    borderColor: '#1f2937',
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
    fontSize: 18,
    color: '#f9fafb',
    backgroundColor: '#1f2937',
    letterSpacing: 4,
    textAlign: 'center',
  },
  button: {
    backgroundColor: '#2563eb',
    borderRadius: 12,
  },
  buttonPressed: {
    opacity: 0.85,
  },
  buttonLabel: {
    color: '#ffffff',
    textAlign: 'center',
    paddingVertical: 14,
    fontWeight: '600',
    fontSize: 16,
  },
  secondaryButton: {
    borderRadius: 12,
    backgroundColor: '#1f2937',
    borderWidth: 1,
    borderColor: '#374151',
  },
  secondaryButtonLabel: {
    color: '#f9fafb',
    textAlign: 'center',
    paddingVertical: 14,
    fontWeight: '600',
    fontSize: 16,
  },
  linkButton: {
    alignSelf: 'center',
  },
  linkText: {
    color: '#93c5fd',
    fontSize: 14,
    textDecorationLine: 'underline',
  },
});
