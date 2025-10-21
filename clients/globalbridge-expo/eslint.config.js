import js from '@eslint/js';
import globals from 'globals';
import tsParser from '@typescript-eslint/parser';
import tsPlugin from '@typescript-eslint/eslint-plugin';
import reactPlugin from 'eslint-plugin-react';
import reactHooksPlugin from 'eslint-plugin-react-hooks';
import reactNativePlugin from 'eslint-plugin-react-native';

const rootDir = import.meta.dirname;
const reactRecommended = reactPlugin.configs?.recommended ?? { rules: {} };
const reactHooksRecommended = reactHooksPlugin.configs?.recommended ?? { rules: {} };
const reactNativeRecommended = reactNativePlugin.configs?.recommended ?? { rules: {} };

export default [
  {
    ignores: [
      'node_modules',
      'dist',
      'build',
      'coverage',
      '.expo',
      '.expo-shared',
    ],
  },
  js.configs.recommended,
  {
    files: ['**/*.{ts,tsx,js,jsx}'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        project: `${rootDir}/tsconfig.json`,
        tsconfigRootDir: rootDir,
        ecmaFeatures: { jsx: true },
        sourceType: 'module',
      },
      globals: {
        ...globals.browser,
        ...globals.node,
      },
    },
    plugins: {
      '@typescript-eslint': tsPlugin,
      react: reactPlugin,
      'react-hooks': reactHooksPlugin,
      'react-native': reactNativePlugin,
    },
    settings: {
      react: { version: 'detect' },
    },
    rules: {
      ...reactRecommended.rules,
      ...reactHooksRecommended.rules,
      ...reactNativeRecommended.rules,
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
      'no-unused-vars': 'off',
      'react/react-in-jsx-scope': 'off',
      'react/prop-types': 'off',
      'react-native/no-inline-styles': 'off',
      'react-native/split-platform-components': 'off',
      'react-native/no-raw-text': 'off',
    },
  },
];
