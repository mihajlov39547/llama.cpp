const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');

function setup() {
  const events = {};
  const calls = [];
  class Element {
    constructor(href) { this.href = href; }
    matches() { return true; }
  }
  class HTMLFormElement {
    constructor(action) { this.action = action; }
    submit() { calls.push(['submit', this.action]); }
  }
  const window = {
    open(...args) { calls.push(args); return 'opened'; },
    addEventListener(name, handler) { events[name] = handler; }
  };
  vm.runInNewContext(fs.readFileSync(path.join(root, 'src/piratebay-guard.js'), 'utf8'), {
    URL, window, document: { baseURI: 'https://piratebay.party/search' },
    Element, HTMLFormElement
  });
  return { window, events, calls, Element, HTMLFormElement };
}

test('direct popup destinations are blocked using hostname boundaries', () => {
  const { window, calls } = setup();
  for (const url of [
    'https://ultimatesurferprotector.com/',
    '//ads.ultimatesurferprotector.com/path',
    'https://ULTIMATESURFERPROTECTOR.COM./',
    'http://ultimatesurferprotector.com:8080/'
  ]) assert.equal(window.open(url), null);
  assert.equal(calls.length, 0);
  for (const url of [
    '/browse', 'about:blank', 'magnet:?xt=urn:btih:example',
    'https://notultimatesurferprotector.com/',
    'https://ultimatesurferprotector.com.example.org/',
    'https://example.org/?url=ultimatesurferprotector.com',
    'https://ultimatesurferprotector.com@example.org/'
  ]) assert.equal(window.open(url, '_blank'), 'opened');
  assert.equal(calls.length, 7);
});

test('click and middle-click block nested link targets without cancelling normal links', () => {
  const { events, Element } = setup();
  for (const type of ['click', 'auxclick']) {
    for (const blocked of [true, false]) {
      let prevented = false;
      let stopped = false;
      events[type]({
        composedPath: () => [{}, new Element(blocked
          ? 'https://ultimatesurferprotector.com/' : 'https://example.org/')],
        preventDefault() { prevented = true; },
        stopImmediatePropagation() { stopped = true; }
      });
      assert.equal(prevented, blocked);
      assert.equal(stopped, blocked);
    }
  }
});

test('forms honor submitter overrides and programmatic submit', () => {
  const { events, HTMLFormElement, calls } = setup();
  const form = new HTMLFormElement('https://example.org/');
  let prevented = false;
  events.submit({ target: form,
    submitter: { hasAttribute: () => true, formAction: 'https://ultimatesurferprotector.com/' },
    preventDefault() { prevented = true; }, stopImmediatePropagation() {}
  });
  assert.equal(prevented, true);
  form.submit();
  new HTMLFormElement('https://ultimatesurferprotector.com/').submit();
  assert.deepEqual(calls, [['submit', 'https://example.org/']]);
});

test('manifest resources exist and network blocking is scoped to requested sites', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
  const rules = JSON.parse(fs.readFileSync(path.join(root, 'rules/piratebay.json')));
  for (const script of manifest.content_scripts) {
    for (const file of [...(script.js || []), ...(script.css || [])]) {
      assert.ok(fs.existsSync(path.join(root, file)), file);
    }
  }
  assert.deepEqual(rules[0].condition.initiatorDomains, ['piratebay.party']);
  assert.deepEqual(rules[0].condition.requestDomains, ['ultimatesurferprotector.com']);
  assert.ok(rules[0].condition.resourceTypes.includes('main_frame'));
  assert.equal(rules[0].action.type, 'block');
});
