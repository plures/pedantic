import { it } from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

it('locks extension dependencies to credential-free public npm sources', () => {
  const lock: { packages: Record<string, { resolved?: string }> } = JSON.parse(
    fs.readFileSync(path.resolve(__dirname, '../../package-lock.json'), 'utf-8')
  );

  for (const [name, dependency] of Object.entries(lock.packages)) {
    if (name === '') {
      continue;
    }
    assert.ok(dependency.resolved, `${name} must have a locked source`);
    const source = new URL(dependency.resolved);
    assert.equal(source.origin, 'https://registry.npmjs.org', `${name} must use public npm`);
    assert.equal(source.username, '', `${name} must not contain registry credentials`);
    assert.equal(source.password, '', `${name} must not contain registry credentials`);
    assert.equal(source.search, '', `${name} must not contain registry query parameters`);
    assert.equal(source.hash, '', `${name} must not contain a registry fragment`);
  }
});
