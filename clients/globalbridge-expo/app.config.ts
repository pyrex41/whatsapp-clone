import type { ConfigContext, ExpoConfig } from 'expo/config';

function readEnv(key: string, fallback: string) {
  const value = process.env[key];
  return typeof value === 'string' && value.length > 0 ? value : fallback;
}

function optionalEnv(key: string) {
  const value = process.env[key];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

export default ({ config }: ConfigContext): ExpoConfig => {
  const apiUrl = readEnv('EXPO_PUBLIC_API_URL', 'http://localhost:4000/api');
  const auth0Domain = optionalEnv('EXPO_PUBLIC_AUTH0_DOMAIN');
  const auth0ClientId = optionalEnv('EXPO_PUBLIC_AUTH0_CLIENT_ID');
  const auth0Audience = optionalEnv('EXPO_PUBLIC_AUTH0_AUDIENCE');
  const easProjectId = readEnv('EAS_PROJECT_ID', '');
  const updatesUrl = optionalEnv('EXPO_UPDATES_URL');

  const extraConfig: Record<string, unknown> = {};
  extraConfig.apiUrl = apiUrl;
  if (auth0Domain) extraConfig.auth0Domain = auth0Domain;
  if (auth0ClientId) extraConfig.auth0ClientId = auth0ClientId;
  if (auth0Audience) extraConfig.auth0Audience = auth0Audience;
  extraConfig.eas = { projectId: easProjectId };

  const updatesConfig: ExpoConfig['updates'] | undefined = updatesUrl
    ? { url: updatesUrl }
    : undefined;

  return {
    ...config,
    name: 'GlobalBridge Expo',
    slug: 'globalbridge-expo',
    version: '1.0.0',
    orientation: 'portrait',
    scheme: 'globalbridge',
    newArchEnabled: true,
    icon: './assets/icon.png',
    userInterfaceStyle: 'light',
    splash: {
      image: './assets/splash-icon.png',
      resizeMode: 'contain',
      backgroundColor: '#ffffff',
    },
    ios: {
      supportsTablet: true,
      bundleIdentifier: 'com.globalbridge.expo',
    },
    android: {
      package: 'com.globalbridge.expo',
      adaptiveIcon: {
        foregroundImage: './assets/adaptive-icon.png',
        backgroundColor: '#ffffff',
      },
      edgeToEdgeEnabled: true,
      allowBackup: false,
      softwareKeyboardLayoutMode: 'pan',
    },
    web: {
      favicon: './assets/favicon.png',
    },
    plugins: [
      [
        'expo-router',
        {
          origin: 'https://globalbridge.app',
        },
      ],
      'expo-secure-store',
    ],
    experiments: {
      typedRoutes: true,
    },
    extra: extraConfig,
    updates: updatesConfig,
    runtimeVersion: '1.0.0',
  };
};
