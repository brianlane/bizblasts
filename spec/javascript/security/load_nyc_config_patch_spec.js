describe('@istanbuljs/load-nyc-config vendor patch', () => {
  test('resolves to the vendored copy under vendor/npm', () => {
    const pkgJson = require('@istanbuljs/load-nyc-config/package.json');
    expect(pkgJson.bizblastsVendorNote).toBeDefined();
  });

  test('depends on js-yaml 4.x to keep the CVE patched', () => {
    const pkgJson = require('@istanbuljs/load-nyc-config/package.json');
    expect(pkgJson.dependencies['js-yaml']).toMatch(/^\^4\./);

    const installedJsYaml = require('js-yaml/package.json');
    expect(Number(installedJsYaml.version.split('.')[0])).toBeGreaterThanOrEqual(4);
  });
});

