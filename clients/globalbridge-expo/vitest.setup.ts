import '@testing-library/jest-native/extend-expect';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

// Ensure React Native Reanimated doesn't blow up in tests
// eslint-disable-next-line @typescript-eslint/no-var-requires
require('react-native-reanimated').setUpTests?.();

afterEach(() => {
  cleanup();
});
