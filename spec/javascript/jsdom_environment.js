// Custom Jest test environment that extends `jest-environment-jsdom` to expose
// the underlying JSDOM instance to tests as `global.jsdomInstance`.
//
// Why: jsdom >= 22 (shipped with jest-environment-jsdom@30) makes
// `window.location` a non-configurable accessor. That means the old
// `delete window.location; window.location = { ... }` (or
// `Object.defineProperty(window, 'location', ...)`) pattern no longer works.
//
// The jsdom-sanctioned replacement is `dom.reconfigure({ url })`, which
// updates `window.location` (including origin, host, port, pathname, etc.).
// Tests can access it via the `jsdomInstance` global exposed below.

const JSDOMEnvironment = require('jest-environment-jsdom').default;

class CustomJsdomEnvironment extends JSDOMEnvironment {
  constructor(config, context) {
    super(config, context);
    this.global.jsdomInstance = this.dom;
  }
}

module.exports = CustomJsdomEnvironment;
