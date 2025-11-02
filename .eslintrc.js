module.exports = {
  env: {
    browser: true,
    es2021: true,
    jest: true,
    node: true
  },
  extends: [
    'eslint:recommended'
  ],
  parserOptions: {
    ecmaVersion: 2022,
    sourceType: 'module',
    ecmaFeatures: {
      impliedStrict: true
    }
  },
  rules: {
    // Code Quality
    'no-unused-vars': ['warn', {
      argsIgnorePattern: '^_',
      varsIgnorePattern: '^_'
    }],
    'no-console': 'off', // Allow console for debugging in admin interface
    'no-debugger': 'warn',

    // Best Practices
    'eqeqeq': ['error', 'always', { null: 'ignore' }],
    'no-eval': 'error',
    'no-implied-eval': 'error',
    'no-new-func': 'error',
    'no-var': 'warn',
    'prefer-const': 'warn',
    'no-loop-func': 'warn',

    // Code Style (consistent with existing code)
    'quotes': ['warn', 'single', { avoidEscape: true }],
    'semi': ['warn', 'always'],
    'indent': ['warn', 2, { SwitchCase: 1 }],
    'comma-dangle': ['warn', 'never'],
    'max-len': ['warn', {
      code: 120,
      ignoreUrls: true,
      ignoreStrings: true,
      ignoreTemplateLiterals: true,
      ignoreComments: true
    }],

    // Security
    'no-script-url': 'error',
    'no-new-wrappers': 'error',

    // Performance
    'no-constant-condition': ['error', { checkLoops: false }]
  },
  overrides: [
    {
      // Test files - more relaxed rules
      files: ['**/*.spec.js', '**/*.test.js', '**/spec/**/*.js'],
      env: {
        jest: true
      },
      rules: {
        'no-unused-vars': 'off',
        'max-len': 'off',
        'no-script-url': 'off' // Allow script URLs in tests to verify they're blocked
      }
    }
  ],
  ignorePatterns: [
    'node_modules/',
    'app/assets/builds/',
    'public/',
    'vendor/',
    'tmp/',
    'coverage/'
  ]
};
