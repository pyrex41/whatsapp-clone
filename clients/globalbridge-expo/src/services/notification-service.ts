import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';

import { useSession } from '~/hooks/use-session';

// Configure notification handler
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

// Notification types
export type BridgeNotificationType = 'bridge_connected' | 'bridge_disconnected' | 'bridge_error';

export interface BridgeNotificationData {
  bridge_id: string;
  bridge_type: string;
  status: string;
  phone_number: string;
  error_message?: string;
}

export class NotificationService {
  private static instance: NotificationService;

  static getInstance(): NotificationService {
    if (!NotificationService.instance) {
      NotificationService.instance = new NotificationService();
    }
    return NotificationService.instance;
  }

  async requestPermissions(): Promise<boolean> {
    const { status } = await Notifications.requestPermissionsAsync();
    return status === 'granted';
  }

  async getDeviceToken(): Promise<string | null> {
    try {
      const token = await Notifications.getDevicePushTokenAsync();
      return token.data;
    } catch (error) {
      console.error('Failed to get device token:', error);
      return null;
    }
  }

  async showBridgeNotification(
    type: BridgeNotificationType,
    data: BridgeNotificationData
  ): Promise<void> {
    const { bridge_type, phone_number, status, error_message } = data;

    let title: string;
    let body: string;
    let sound: 'default' | 'critical' = 'default';

    switch (type) {
      case 'bridge_connected':
        title = `${bridge_type.charAt(0).toUpperCase() + bridge_type.slice(1)} Connected`;
        body = `${bridge_type.charAt(0).toUpperCase() + bridge_type.slice(1)} bridge for ${phone_number} is now connected and syncing messages.`;
        break;
      case 'bridge_disconnected':
        title = `${bridge_type.charAt(0).toUpperCase() + bridge_type.slice(1)} Disconnected`;
        body = `${bridge_type.charAt(0).toUpperCase() + bridge_type.slice(1)} bridge for ${phone_number} has been disconnected.`;
        sound = 'default';
        break;
      case 'bridge_error':
        title = `${bridge_type.charAt(0).toUpperCase() + bridge_type.slice(1)} Error`;
        body = `${bridge_type.charAt(0).toUpperCase() + bridge_type.slice(1)} bridge for ${phone_number} encountered an error: ${error_message || 'Unknown error'}`;
        sound = 'critical';
        break;
      default:
        return;
    }

    await Notifications.scheduleNotificationAsync({
      content: {
        title,
        body,
        sound,
        data: {
          type,
          bridge_id: data.bridge_id,
          bridge_type: data.bridge_type,
          status: data.status,
          phone_number: data.phone_number,
        },
      },
      trigger: null, // Show immediately
    });
  }

  async showLocalNotification(title: string, body: string, data?: any): Promise<void> {
    await Notifications.scheduleNotificationAsync({
      content: {
        title,
        body,
        sound: 'default',
        data: data || {},
      },
      trigger: null,
    });
  }

  // Set up notification listeners
  setupNotificationListeners(): void {
    // Handle notification received while app is foregrounded
    const receivedSubscription = Notifications.addNotificationReceivedListener(notification => {
      console.log('Notification received:', notification);
      // Handle foreground notification if needed
    });

    // Handle notification tapped
    const tappedSubscription = Notifications.addNotificationResponseReceivedListener(response => {
      console.log('Notification tapped:', response);
      const data = response.notification.request.content.data;

      // Handle different notification types
      if (data?.type?.startsWith('bridge_')) {
        // Navigate to bridge setup screen or show bridge details
        // This would be handled by navigation logic
      }
    });

    // Store subscriptions for cleanup if needed
    this.receivedSubscription = receivedSubscription;
    this.tappedSubscription = tappedSubscription;
  }

  // Clean up listeners
  cleanup(): void {
    if (this.receivedSubscription) {
      Notifications.removeNotificationSubscription(this.receivedSubscription);
    }
    if (this.tappedSubscription) {
      Notifications.removeNotificationSubscription(this.tappedSubscription);
    }
  }

  private receivedSubscription?: Notifications.Subscription;
  private tappedSubscription?: Notifications.Subscription;
}

// Hook for using notification service
export function useNotifications() {
  const notificationService = NotificationService.getInstance();

  return {
    requestPermissions: () => notificationService.requestPermissions(),
    getDeviceToken: () => notificationService.getDeviceToken(),
    showBridgeNotification: (type: BridgeNotificationType, data: BridgeNotificationData) =>
      notificationService.showBridgeNotification(type, data),
    showLocalNotification: (title: string, body: string, data?: any) =>
      notificationService.showLocalNotification(title, body, data),
    setupListeners: () => notificationService.setupNotificationListeners(),
    cleanup: () => notificationService.cleanup(),
  };
}