// Jest setup file for BizBlasts JavaScript tests

// Mock console methods to reduce noise in tests
global.console = {
  ...console
  // Uncomment to ignore specific console methods during tests
  // log: jest.fn(),
  // warn: jest.fn(),
  // error: jest.fn(),
};

// Mock window.location
delete window.location;
window.location = {
  href: 'http://localhost:3000',
  host: 'localhost:3000',
  hostname: 'localhost',
  port: '3000',
  protocol: 'http:',
  pathname: '/',
  search: '',
  hash: ''
};

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