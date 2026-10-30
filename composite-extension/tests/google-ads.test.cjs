const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

test('global ad hiding is CSS only and network blocking remains Pirate Bay scoped', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
  const globalScripts = manifest.content_scripts.filter(script =>
    script.matches.includes('https://*/*'));
  assert.equal(globalScripts.length, 1);
  assert.deepEqual(globalScripts[0].css, ['src/google-ads.css', 'src/billboards.css']);
  assert.equal(globalScripts[0].js, undefined);
  assert.equal(globalScripts[0].all_frames, true);
  const rules = manifest.declarative_net_request.rule_resources.flatMap(resource =>
    JSON.parse(fs.readFileSync(path.join(root, resource.path))));
  assert.equal(rules.length, 1);
  assert.deepEqual(rules[0].condition.initiatorDomains, ['piratebay.party']);
  assert.deepEqual(rules[0].condition.requestDomains, ['ultimatesurferprotector.com']);
});
