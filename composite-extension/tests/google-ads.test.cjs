const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');

test('cleanup removes initial and late ads, preserving ordinary elements', () => {
  class Element {
    constructor(ad = false, children = []) {
      this.ad = ad;
      this.children = children;
      this.removed = false;
    }
    matches() { return this.ad; }
    querySelectorAll() { return this.children.filter(child => child.ad); }
    remove() { this.removed = true; }
  }
  const initialAd = new Element(true);
  const normal = new Element();
  const document = new Element(false, [initialAd, normal]);
  let notify;
  class MutationObserver {
    constructor(callback) { notify = callback; }
    observe() {}
  }
  vm.runInNewContext(fs.readFileSync(path.join(root, 'src/google-ads.js'), 'utf8'), {
    document, Element, MutationObserver
  });
  assert.equal(initialAd.removed, true);
  assert.equal(normal.removed, false);
  const lateAd = new Element(true);
  notify([{ type: 'childList', addedNodes: [new Element(false, [lateAd]), normal] }]);
  assert.equal(lateAd.removed, true);
  assert.equal(normal.removed, false);
  normal.ad = true;
  notify([{ type: 'attributes', target: normal }]);
  assert.equal(normal.removed, true);
});

test('all registered rulesets parse and Google rules cover the supplied iframe globally', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
  const rules = manifest.declarative_net_request.rule_resources.flatMap(resource =>
    JSON.parse(fs.readFileSync(path.join(root, resource.path))));
  assert.equal(new Set(rules.map(rule => rule.id)).size, rules.length);
  const googleRule = rules.find(rule => rule.id === 100);
  const host = new URL('https://googleads.g.doubleclick.net/pagead/html/example.html').hostname;
  assert.ok(googleRule.condition.requestDomains.some(domain => host === domain || host.endsWith(`.${domain}`)));
  assert.equal(googleRule.condition.initiatorDomains, undefined);
  assert.deepEqual(googleRule.condition.excludedResourceTypes, ['main_frame']);
  const cleanup = manifest.content_scripts.find(script => script.js?.includes('src/google-ads.js'));
  assert.deepEqual(cleanup.matches, ['http://*/*', 'https://*/*']);
  assert.equal(cleanup.all_frames, true);
});
