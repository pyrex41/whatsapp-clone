import { createContext, PropsWithChildren, useContext, useEffect } from 'react';

import { useNotifications } from '~/services/notification-service';

interface NotificationContextType {
  requestPermissions: () => Promise<boolean>;
  getDeviceToken: () => Promise<string | null>;
}

const NotificationContext = createContext<NotificationContextType | null>(null);

export function NotificationProvider({ children }: PropsWithChildren) {
  const notifications = useNotifications();

  useEffect(() => {
    // Set up notification listeners when the provider mounts
    notifications.setupListeners();

    // Request permissions on app start
    notifications.requestPermissions().catch(error => {
      console.error('Failed to request notification permissions:', error);
    });

    // Cleanup listeners when provider unmounts
    return () => {
      notifications.cleanup();
    };
  }, [notifications]);

  const value = {
    requestPermissions: notifications.requestPermissions,
    getDeviceToken: notifications.getDeviceToken,
  };

  return (
    <NotificationContext.Provider value={value}>
      {children}
    </NotificationContext.Provider>
  );
}

export function useNotificationContext() {
  const context = useContext(NotificationContext);
  if (!context) {
    throw new Error('useNotificationContext must be used within a NotificationProvider');
  }
  return context;
}