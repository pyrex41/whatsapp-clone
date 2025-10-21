import { useCallback, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

import { useSessionActions, useSessionStatus } from '~/hooks/use-session';

export default function LoginScreen() {
  const { status, error } = useSessionStatus();
  const { login, loginWithAuth0, clearError } = useSessionActions();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useFocusEffect(
    useCallback(() => {
      return () => {
        clearError();
        setPassword('');
      };
    }, [clearError]),
  );

  useFocusEffect(
    useCallback(() => {
      if (!error) return;
      Alert.alert('Sign in failed', error, [{ text: 'Dismiss', onPress: clearError }]);
    }, [clearError, error]),
  );

  const onSubmit = useCallback(async () => {
    if (submitting) return;
    setSubmitting(true);
    try {
      await login(email.trim(), password);
    } finally {
      setSubmitting(false);
    }
  }, [email, login, password, submitting]);

  const onAuth0 = useCallback(async () => {
    if (submitting) return;
    setSubmitting(true);
    try {
      await loginWithAuth0();
    } finally {
      setSubmitting(false);
    }
  }, [loginWithAuth0, submitting]);

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>GlobalBridge</Text>
        <Text style={styles.subtitle}>Connect your messaging worlds</Text>
      </View>

      <View style={styles.form}>
        <Pressable
          accessibilityRole="button"
          onPress={onAuth0}
          style={({ pressed }) => [styles.buttonSSO, pressed && styles.buttonPressed]}
        >
          <Text style={styles.buttonLabel}>Sign in with Auth0</Text>
        </Pressable>

        <Text style={styles.orText}>or use email</Text>
        <Text style={styles.label}>Email</Text>
        <TextInput
          autoCapitalize="none"
          keyboardType="email-address"
          placeholder="you@example.com"
          value={email}
          onChangeText={setEmail}
          style={styles.input}
          editable={!submitting && status !== 'authenticating'}
        />

        <Text style={styles.label}>Password</Text>
        <TextInput
          secureTextEntry
          placeholder="••••••••"
          value={password}
          onChangeText={setPassword}
          style={styles.input}
          editable={!submitting && status !== 'authenticating'}
          onSubmitEditing={onSubmit}
        />

        <Pressable
          accessibilityRole="button"
          onPress={onSubmit}
          disabled={submitting || !email || !password}
          style={({ pressed }) => [
            styles.button,
            (submitting || !email || !password) && styles.buttonDisabled,
            pressed && styles.buttonPressed,
          ]}
        >
          <Text style={styles.buttonLabel}>
            {submitting || status === 'authenticating' ? 'Signing in…' : 'Sign in'}
          </Text>
        </Pressable>
      </View>

      <View style={styles.footer} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 24,
    backgroundColor: '#ffffff',
    justifyContent: 'center',
  },
  header: {
    marginBottom: 32,
  },
  title: {
    fontSize: 32,
    fontWeight: '700',
    color: '#111827',
  },
  subtitle: {
    fontSize: 16,
    color: '#4b5563',
    marginTop: 4,
  },
  form: {
    gap: 16,
  },
  orText: {
    textAlign: 'center',
    color: '#6b7280',
    marginVertical: 8,
  },
  label: {
    fontSize: 14,
    color: '#374151',
  },
  input: {
    borderWidth: 1,
    borderColor: '#d1d5db',
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
    fontSize: 16,
    backgroundColor: '#f9fafb',
  },
  button: {
    marginTop: 12,
    backgroundColor: '#2563eb',
    borderRadius: 12,
    overflow: 'hidden',
  },
  buttonSSO: {
    backgroundColor: '#111827',
    borderRadius: 12,
    overflow: 'hidden',
  },
  buttonPressed: {
    opacity: 0.85,
  },
  buttonDisabled: {
    backgroundColor: '#93c5fd',
  },
  buttonLabel: {
    color: '#ffffff',
    textAlign: 'center',
    paddingVertical: 14,
    fontWeight: '600',
    fontSize: 16,
  },
  footer: {
    marginTop: 32,
    alignItems: 'center',
  },
  link: {
    color: '#2563eb',
    fontSize: 14,
    fontWeight: '500',
  },
});
