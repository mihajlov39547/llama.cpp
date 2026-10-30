const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../src/vendor/rts-cookies.js'), 'utf8');

test('RTS fallback reads real values and supports the site expiry call without startup writes', () => {
  let cookie = 'promo_seen=seen; unrelated=hello%20world';
  const writes = [];
  const document = {
    get cookie() { return cookie; },
    set cookie(value) { writes.push(value); cookie = value; }
  };
  const context = vm.createContext({ document, define: Object.assign(() => { throw Error('AMD called'); }, { amd: true }) });
  vm.runInContext(source, context);
  assert.equal(writes.length, 0);
  assert.equal(context.Cookies.get('promo_seen'), 'seen');
  assert.equal(context.Cookies.get('unrelated'), 'hello world');
  assert.equal(context.Cookies.get('missing'), undefined);
  context.Cookies.set('promo_seen', 'seen', { expires: 14 });
  assert.match(writes[0], /^promo_seen=seen; path=\/; expires=/);
  const expires = new Date(writes[0].split('expires=')[1]).getTime();
  assert.ok(Math.abs(expires - Date.now() - 14 * 86400000) < 3000);
});

test('existing Cookies implementation is preserved', () => {
  const Cookies = { get: () => 'existing' };
  const context = vm.createContext({ Cookies });
  vm.runInContext(source, context);
  assert.equal(context.Cookies, Cookies);
});
