import { useEffect } from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';

import { useSessionActions } from '~/hooks/use-session';

export default function CallbackScreen() {
  const params = useLocalSearchParams<{ token?: string; refreshToken?: string }>();
  const router = useRouter();
  const { loadSession } = useSessionActions();

  useEffect(() => {
    // Placeholder for future SSO exchange.
    // In a future task we'll validate tokens with the backend.
    if (params.token) {
      void loadSession();
      router.replace('/(tabs)');
    }
  }, [loadSession, params.token, router]);

  return (
    <View style={styles.container}>
      <ActivityIndicator size="large" color="#2563eb" />
      <Text style={styles.message}>Finishing sign-in…</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
    backgroundColor: '#ffffff',
  },
  message: {
    fontSize: 16,
    color: '#4b5563',
  },
});
