import assert from 'node:assert/strict';
import { createHash, createPublicKey, verify } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const fixture = JSON.parse(readFileSync(
  new URL('../contracts/v2/fixtures/conformance.json', import.meta.url), 'utf8',
));

// Independent ECMAScript test oracle; production uses the Rust JCS implementation.
function canonical(value) {
  if (typeof value === 'number' &&
      (!Number.isFinite(value) || (Number.isInteger(value) && !Number.isSafeInteger(value)))) {
    throw new Error('unsupported_number');
  }
  if (typeof value === 'string' && !value.isWellFormed()) {
    throw new Error('invalid Unicode');
  }
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key => `${canonical(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

const digest = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;
const payload = authorization => ({
  schemaVersion: authorization.schemaVersion,
  grant: authorization.grant,
});
const key = createPublicKey({
  key: Buffer.concat([
    Buffer.from('302a300506032b6570032100', 'hex'),
    Buffer.from(fixture.publicKey, 'base64url'),
  ]),
  format: 'der',
  type: 'spki',
});

test('shared v2 plan digest and Ed25519 signature agree with Node', () => {
  assert.equal(fixture.fixtureOnly, true);
  assert.equal(digest(fixture.plan), fixture.authorization.grant.planDigest);
  assert.equal(digest(payload(fixture.authorization)), fixture.authorization.signature.payloadDigest);
  assert.equal(verify(
    null,
    Buffer.from(canonical(payload(fixture.authorization))),
    key,
    Buffer.from(fixture.authorization.signature.value, 'base64url'),
  ), true);
});

for (const vector of fixture.canonicalVectors) {
  test(`shared JCS vector: ${vector.name}`, () => {
    assert.equal(canonical(vector.value), vector.canonical);
  });
}

for (const entry of fixture.negativeCases.filter(entry => entry.checkSignature)) {
  test(`shared signature rejection: ${entry.name}`, () => {
    const authorization = structuredClone(fixture.authorization);
    const path = entry.path.slice(1).split('/');
    const leaf = path.pop();
    const parent = path.reduce((object, part) => object[part], authorization);
    parent[leaf] = entry.value;
    assert.equal(verify(
      null,
      Buffer.from(canonical(payload(authorization))),
      key,
      Buffer.from(authorization.signature.value, 'base64url'),
    ), false);
  });
}

test('numeric profile rejects integer values that JavaScript cannot safely identify', () => {
  for (const value of [9007199254740992, -9007199254740992, 1e20, Infinity, NaN]) {
    assert.throws(() => canonical(value), /unsupported_number/);
  }
});
