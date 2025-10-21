module.exports = {
  root: true,
  extends: ['universe/native', 'universe/shared/typescript-analysis'],
  plugins: ['react', 'react-native'],
  rules: {
    'react/react-in-jsx-scope': 'off',
    'react-native/no-unused-styles': 'warn',
    'react-native/split-platform-components': 'off',
    'react-native/no-inline-styles': 'off',
    '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }]
  },
  settings: {
    'import/resolver': {
      'babel-module': {
        root: ['.'],
        alias: {
          '~': './src'
        }
      }
    }
  }
};
