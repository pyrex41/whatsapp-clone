import type { DetoxConfig } from 'detox';

const config: DetoxConfig = {
  logger: {
    level: 'info',
  },
  testRunner: {
    args: {
      $0: 'mocha',
      _: ['./e2e'],
    },
    forwardEnv: true,
  },
  behavior: {
    init: {
      exposeGlobals: false,
    },
  },
  configurations: {
    'ios.sim.debug': {
      device: {
        type: 'ios.simulator',
        device: 'iPhone 15',
      },
      app: {
        type: 'ios.app',
        binaryPath: 'bin/Exponent.app',
      },
      build: 'expo run:ios --scheme globalbridge-expo --configuration Debug',
    },
    'android.emu.debug': {
      device: {
        type: 'android.emulator',
        device: {
          avdName: 'Pixel_7_API_34',
        },
      },
      app: {
        type: 'android.apk',
        binaryPath: 'bin/Exponent.apk',
      },
      build: 'expo run:android --variant debug',
    },
  },
};

export default config;
