/* eslint-disable */
import * as Router from 'expo-router';

export * from 'expo-router';

declare module 'expo-router' {
  export namespace ExpoRouter {
    export interface __routes<T extends string = string> extends Record<string, unknown> {
      StaticRoutes: `/` | `/(auth)` | `/(auth)/callback` | `/(auth)/lock` | `/(auth)/login` | `/(tabs)` | `/(tabs)/` | `/(tabs)/settings` | `/_sitemap` | `/callback` | `/lock` | `/login` | `/settings`;
      DynamicRoutes: `/(tabs)/thread/${Router.SingleRoutePart<T>}` | `/thread/${Router.SingleRoutePart<T>}`;
      DynamicRouteTemplate: `/(tabs)/thread/[threadId]` | `/thread/[threadId]`;
    }
  }
}
