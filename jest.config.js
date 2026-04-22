// Jest configuration for BizBlasts JavaScript tests
module.exports = {
  // Test environment
  // Custom env extends jsdom and exposes the JSDOM instance as `jsdomInstance`
  // so tests can call `jsdomInstance.reconfigure({ url })` to change
  // window.location. Needed because jsdom>=22 makes location non-configurable.
  testEnvironment: '<rootDir>/spec/javascript/jsdom_environment.js',
  testEnvironmentOptions: {
    url: 'http://localhost:3000'
  },

  
  // Test file patterns
  testMatch: [
    '<rootDir>/spec/javascript/**/*_spec.js'
  ],
  
  // Setup files
  setupFilesAfterEnv: ['<rootDir>/spec/javascript/setup.js'],
  
  // Module paths
  moduleNameMapper: {
    '^@hotwired/stimulus$': '<rootDir>/spec/javascript/mocks/stimulus.js',
    '^@hotwired/turbo-rails$': '<rootDir>/spec/javascript/mocks/turbo.js'
  },
  
  // Transform files
  transform: {
    '^.+\\.js$': 'babel-jest'
  },
  
  // Coverage settings
  collectCoverage: false,
  collectCoverageFrom: [
    'app/javascript/**/*.js',
    '!app/javascript/application.js' // Exclude main entry point
  ],
  
  // Ignore patterns
  testPathIgnorePatterns: [
    '/node_modules/',
    '/vendor/',
    '/tmp/'
  ],
  
  // Module file extensions
  moduleFileExtensions: ['js', 'json'],
  
  // Verbose output
  verbose: true,
  
  // Coverage settings
  coverageDirectory: 'coverage/javascript',
  coverageReporters: ['html', 'text', 'lcov']
}; 