// Jest setup file for BizBlasts JavaScript tests

// Mock console methods to reduce noise in tests
global.console = {
  ...console
  // Uncomment to ignore specific console methods during tests
  // log: jest.fn(),
  // warn: jest.fn(),
  // error: jest.fn(),
};

// Initial `window.location` is set via jest.config.js `testEnvironmentOptions.url`.
// To change it during a test, use `jsdomInstance.reconfigure({ url })` (the
// `jsdomInstance` global is exposed by the custom test environment in
// spec/javascript/jsdom_environment.js). jsdom >= 22 makes `window.location`
// a non-configurable accessor, so the old `delete window.location` pattern
// and `Object.defineProperty(window, 'location', ...)` no longer work.

// Mock process.env for tests
global.process = {
  env: {
    NODE_ENV: 'test'
  }
};

// Setup DOM globals
global.document = window.document;
global.window = window;
global.navigator = window.navigator;

// Mock URL constructor for older environments
if (typeof URL === 'undefined') {
  global.URL = require('url').URL;
}

// Add custom matchers or global test utilities here
// Example:
// expect.extend({
//   toBeVisible(received) {
//     const pass = received.style.display !== 'none';
//     return {
//       message: () => `expected element to ${pass ? 'not ' : ''}be visible`,
//       pass,
//     };
//   },
// }); 