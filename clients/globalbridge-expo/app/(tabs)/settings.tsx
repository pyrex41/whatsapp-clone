import { useCallback } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';

import { useSession, useSessionActions } from '~/hooks/use-session';

export default function SettingsScreen() {
  const { logout, toggleBiometrics, setPin } = useSessionActions();
  const preferences = useSession((state) => state.preferences);
  const biometricsSupported = useSession((state) => state.biometricsSupported);
  const pinConfigured = useSession((state) => state.pinConfigured);
  const user = useSession((state) => state.tokens?.user);

  const onToggleBiometrics = useCallback(
    (value: boolean) => {
      if (!biometricsSupported) {
        Alert.alert('Biometrics unavailable', 'Your device does not support biometrics.');
        return;
      }
      void toggleBiometrics(value);
    },
    [biometricsSupported, toggleBiometrics],
  );

  const onSetPin = useCallback(() => {
    if (typeof Alert.prompt === 'function') {
      Alert.prompt(
        pinConfigured ? 'Update PIN' : 'Create PIN',
        pinConfigured ? 'Enter a new 6-digit PIN.' : 'Set a 6-digit PIN to secure the app.',
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Save',
            style: 'default',
            onPress: (value) => {
              if (!value || value.length < 4) {
                Alert.alert('PIN too short', 'Please use at least 4 digits.');
                return;
              }
              void setPin(value);
            },
          },
        ],
        'secure-text',
      );
      return;
    }

    Alert.alert(
      pinConfigured ? 'PIN required' : 'Set up a PIN',
      'PIN entry is available on iOS at the moment. We will add an Android-friendly flow soon.',
    );
  }, [pinConfigured, setPin]);

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Account</Text>
        <View style={styles.row}>
          <Text style={styles.label}>Signed in as</Text>
          <Text style={styles.value}>{user?.email ?? 'Unknown user'}</Text>
        </View>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Security</Text>
        <View style={styles.row}>
          <Text style={styles.label}>Biometric unlock</Text>
          <Switch
            value={preferences.biometricsEnabled}
            onValueChange={onToggleBiometrics}
            disabled={!biometricsSupported}
          />
        </View>
        <Pressable
          style={({ pressed }) => [styles.linkRow, pressed && styles.linkRowPressed]}
          onPress={onSetPin}
        >
          <Text style={styles.label}>{pinConfigured ? 'Update PIN' : 'Create PIN'}</Text>
          <Text style={styles.value}>{pinConfigured ? 'Configured' : 'Not set'}</Text>
        </Pressable>
      </View>

      <View style={styles.section}>
        <Pressable
          style={({ pressed }) => [styles.dangerButton, pressed && styles.dangerButtonPressed]}
          onPress={() => {
            Alert.alert('Sign out', 'Are you sure you want to sign out?', [
              { text: 'Cancel', style: 'cancel' },
              { text: 'Sign out', style: 'destructive', onPress: logout },
            ]);
          }}
        >
          <Text style={styles.dangerLabel}>Sign out</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 24,
    gap: 24,
  },
  section: {
    backgroundColor: '#ffffff',
    borderRadius: 16,
    padding: 20,
    gap: 16,
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 6 },
    elevation: 3,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#111827',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  label: {
    fontSize: 16,
    color: '#4b5563',
  },
  value: {
    fontSize: 16,
    color: '#111827',
    fontWeight: '500',
  },
  linkRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 4,
  },
  linkRowPressed: {
    opacity: 0.8,
  },
  dangerButton: {
    borderRadius: 12,
    paddingVertical: 14,
    backgroundColor: '#f87171',
  },
  dangerButtonPressed: {
    opacity: 0.85,
  },
  dangerLabel: {
    textAlign: 'center',
    fontSize: 16,
    color: '#ffffff',
    fontWeight: '600',
  },
});
