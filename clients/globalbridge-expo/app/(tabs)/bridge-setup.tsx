import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useRouter } from 'expo-router';

import { useBridges } from '~/hooks/use-bridges';

export default function BridgeSetupScreen() {
  const router = useRouter();
  const { bridges, isLoading, error, refetch, createBridge, toggleBridgeActive, deleteBridge } = useBridges();
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [phoneNumber, setPhoneNumber] = useState('');
  const [isCreating, setIsCreating] = useState(false);

  const handleRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await refetch();
    setIsRefreshing(false);
  }, [refetch]);

  const handleCreateBridge = useCallback(async () => {
    if (!phoneNumber.trim()) {
      Alert.alert('Error', 'Please enter a phone number');
      return;
    }

    // Basic phone number validation
    const phoneRegex = /^\+[1-9]\d{1,14}$/;
    if (!phoneRegex.test(phoneNumber.trim())) {
      Alert.alert('Error', 'Please enter a valid phone number (e.g., +1234567890)');
      return;
    }

    setIsCreating(true);
    try {
      await createBridge({
        bridge_type: 'telegram',
        phone_number: phoneNumber.trim(),
      });

      setPhoneNumber('');
      setShowCreateForm(false);
      Alert.alert('Success', 'Bridge created successfully! Check your Telegram app for the verification code.');
    } catch (error: any) {
      const errorMessage = error?.message || 'Failed to create bridge';
      Alert.alert('Error', errorMessage);
      console.error('Failed to create bridge:', error);
    } finally {
      setIsCreating(false);
    }
  }, [createBridge, phoneNumber]);

  const handleToggleActive = useCallback(async (bridge: ApiBridge) => {
    try {
      await toggleBridgeActive(bridge.id, !bridge.is_active);
    } catch (error) {
      Alert.alert('Error', 'Failed to update bridge status');
      console.error('Failed to toggle bridge active:', error);
    }
  }, [toggleBridgeActive]);

  const handleDeleteBridge = useCallback((bridge: ApiBridge) => {
    Alert.alert(
      'Delete Bridge',
      `Are you sure you want to delete the ${bridge.bridge_type} bridge for ${bridge.phone_number}?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              await deleteBridge(bridge.id);
              Alert.alert('Success', 'Bridge deleted successfully');
            } catch (error) {
              Alert.alert('Error', 'Failed to delete bridge');
              console.error('Failed to delete bridge:', error);
            }
          },
        },
      ],
    );
  }, [deleteBridge]);

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'connected':
        return '#10b981'; // green
      case 'connecting':
        return '#f59e0b'; // yellow
      case 'error':
        return '#ef4444'; // red
      default:
        return '#6b7280'; // gray
    }
  };

  const getStatusText = (status: string) => {
    switch (status) {
      case 'connected':
        return 'Connected';
      case 'connecting':
        return 'Connecting...';
      case 'error':
        return 'Error';
      default:
        return 'Disconnected';
    }
  };

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#2563eb" />
        <Text style={styles.loadingText}>Loading bridges...</Text>
      </View>
    );
  }

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.content}
      refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={handleRefresh} />}
    >
      <View style={styles.header}>
        <Text style={styles.title}>Bridge Setup</Text>
        <Text style={styles.subtitle}>Connect external messaging services to sync conversations</Text>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Your Bridges</Text>

        {bridges.length === 0 ? (
          <View style={styles.emptyState}>
            <Text style={styles.emptyTitle}>No bridges configured</Text>
            <Text style={styles.emptySubtitle}>Add a bridge below to start syncing messages from external services.</Text>
          </View>
        ) : (
          <FlatList
            data={bridges}
            keyExtractor={(item) => item.id}
            renderItem={({ item }) => (
              <View style={styles.bridgeCard}>
                <View style={styles.bridgeHeader}>
                  <View style={styles.bridgeInfo}>
                    <Text style={styles.bridgeType}>{item.bridge_type.toUpperCase()}</Text>
                    <Text style={styles.bridgePhone}>{item.phone_number}</Text>
                  </View>
                  <View style={styles.bridgeActions}>
                    <View style={[styles.statusIndicator, { backgroundColor: getStatusColor(item.status) }]}>
                      <Text style={styles.statusText}>{getStatusText(item.status)}</Text>
                    </View>
                  </View>
                </View>

                <View style={styles.bridgeControls}>
                  <View style={styles.controlRow}>
                    <Text style={styles.controlLabel}>Active</Text>
                    <Switch
                      value={item.is_active}
                      onValueChange={() => handleToggleActive(item)}
                      disabled={item.status === 'connecting'}
                    />
                  </View>

                  <Pressable
                    style={({ pressed }) => [styles.deleteButton, pressed && styles.deleteButtonPressed]}
                    onPress={() => handleDeleteBridge(item)}
                  >
                    <Text style={styles.deleteButtonText}>Delete Bridge</Text>
                  </Pressable>
                </View>

                {item.error_message && (
                  <View style={styles.errorBanner}>
                    <Text style={styles.errorText}>{item.error_message}</Text>
                  </View>
                )}
              </View>
            )}
            scrollEnabled={false}
          />
        )}
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Add New Bridge</Text>

        {!showCreateForm ? (
          <Pressable
            style={({ pressed }) => [styles.addButton, pressed && styles.addButtonPressed]}
            onPress={() => setShowCreateForm(true)}
          >
            <Text style={styles.addButtonText}>+ Add Telegram Bridge</Text>
          </Pressable>
        ) : (
          <View style={styles.createForm}>
            <Text style={styles.formLabel}>Phone Number</Text>
            <TextInput
              style={styles.phoneInput}
              value={phoneNumber}
              onChangeText={setPhoneNumber}
              placeholder="+1234567890"
              keyboardType="phone-pad"
              autoCapitalize="none"
              autoCorrect={false}
            />

            <View style={styles.formActions}>
              <Pressable
                style={({ pressed }) => [styles.cancelButton, pressed && styles.cancelButtonPressed]}
                onPress={() => {
                  setShowCreateForm(false);
                  setPhoneNumber('');
                }}
              >
                <Text style={styles.cancelButtonText}>Cancel</Text>
              </Pressable>

              <Pressable
                style={({ pressed }) => [styles.createButton, pressed && styles.createButtonPressed, isCreating && styles.createButtonDisabled]}
                onPress={handleCreateBridge}
                disabled={isCreating}
              >
                {isCreating ? (
                  <ActivityIndicator size="small" color="#ffffff" />
                ) : (
                  <Text style={styles.createButtonText}>Create Bridge</Text>
                )}
              </Pressable>
            </View>
          </View>
        )}
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f9fafb',
  },
  content: {
    padding: 24,
    gap: 24,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 12,
  },
  loadingText: {
    fontSize: 16,
    color: '#4b5563',
  },
  header: {
    gap: 8,
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
    color: '#111827',
  },
  subtitle: {
    fontSize: 16,
    color: '#4b5563',
  },
  section: {
    backgroundColor: '#ffffff',
    borderRadius: 16,
    padding: 20,
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 6 },
    elevation: 3,
    gap: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#111827',
  },
  emptyState: {
    alignItems: 'center',
    gap: 8,
    paddingVertical: 24,
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#111827',
  },
  emptySubtitle: {
    fontSize: 14,
    color: '#6b7280',
    textAlign: 'center',
  },
  bridgeCard: {
    backgroundColor: '#f9fafb',
    borderRadius: 12,
    padding: 16,
    marginBottom: 12,
    gap: 12,
  },
  bridgeHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  bridgeInfo: {
    flex: 1,
    gap: 4,
  },
  bridgeType: {
    fontSize: 14,
    fontWeight: '600',
    color: '#2563eb',
    textTransform: 'uppercase',
  },
  bridgePhone: {
    fontSize: 16,
    color: '#111827',
    fontWeight: '500',
  },
  bridgeActions: {
    alignItems: 'flex-end',
  },
  statusIndicator: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 12,
  },
  statusText: {
    fontSize: 12,
    color: '#ffffff',
    fontWeight: '600',
  },
  bridgeControls: {
    gap: 12,
  },
  controlRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  controlLabel: {
    fontSize: 16,
    color: '#4b5563',
  },
  deleteButton: {
    backgroundColor: '#fee2e2',
    borderRadius: 8,
    paddingVertical: 8,
    paddingHorizontal: 12,
    alignSelf: 'flex-start',
  },
  deleteButtonPressed: {
    opacity: 0.8,
  },
  deleteButtonText: {
    fontSize: 14,
    color: '#dc2626',
    fontWeight: '600',
  },
  errorBanner: {
    backgroundColor: '#fee2e2',
    borderRadius: 8,
    padding: 12,
  },
  errorText: {
    fontSize: 14,
    color: '#b91c1c',
  },
  addButton: {
    backgroundColor: '#2563eb',
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
  },
  addButtonPressed: {
    opacity: 0.9,
  },
  addButtonText: {
    fontSize: 16,
    color: '#ffffff',
    fontWeight: '600',
  },
  createForm: {
    gap: 16,
  },
  formLabel: {
    fontSize: 16,
    color: '#111827',
    fontWeight: '500',
  },
  phoneInput: {
    borderWidth: 1,
    borderColor: '#d1d5db',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
    backgroundColor: '#ffffff',
  },
  formActions: {
    flexDirection: 'row',
    gap: 12,
  },
  cancelButton: {
    flex: 1,
    backgroundColor: '#f3f4f6',
    borderRadius: 8,
    paddingVertical: 12,
    alignItems: 'center',
  },
  cancelButtonPressed: {
    opacity: 0.8,
  },
  cancelButtonText: {
    fontSize: 16,
    color: '#374151',
    fontWeight: '600',
  },
  createButton: {
    flex: 2,
    backgroundColor: '#10b981',
    borderRadius: 8,
    paddingVertical: 12,
    alignItems: 'center',
  },
  createButtonPressed: {
    opacity: 0.9,
  },
  createButtonDisabled: {
    opacity: 0.6,
  },
  createButtonText: {
    fontSize: 16,
    color: '#ffffff',
    fontWeight: '600',
  },
});