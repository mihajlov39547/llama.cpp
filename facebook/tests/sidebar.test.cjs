const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const context = vm.createContext({ URL });
vm.runInContext(fs.readFileSync(path.join(__dirname, '../src/sidebar-model.js'), 'utf8'), context);
const model = context.BetterFacebookSidebar;
const plain = value => JSON.parse(JSON.stringify(value));

test('menu excludes Friends, external destinations, actions and invalid cached data', () => {
  assert.deepEqual(plain(model.clean([
    { href: '/events?source=46&action_history=null', label: 'Events' },
    { href: '/friends/', label: 'Friends' },
    { href: '/friends/suggestions/', label: 'Suggestions' },
    { href: 'https://evil.example/events', label: 'External' },
    { href: 'javascript:alert(1)', label: 'Script' },
    { href: '/logout.php', label: 'Log out' },
    { href: '/events/', label: 'Duplicate' }, null, { href: '/' }
  ])), [{ href: '/events', label: 'Events' }]);
});
test('profile identity and tracking values are not persisted', () => {
  assert.deepEqual(plain(model.clean([
    { href: '/profile.php?id=123456', label: 'Personal name' },
    { href: '/groups/?source=123', label: 'Groups' }
  ])), [{ href: '/me/', label: 'Your profile' }, { href: '/groups/', label: 'Groups' }]);
});
test('selected destination handles query strings, trailing slashes and child pages', () => {
  assert.equal(model.active('/events/', 'https://www.facebook.com/events?source=46'), true);
  assert.equal(model.active('/events/', '/events/123'), true);
  assert.equal(model.active('/', '/events/'), false);
  assert.equal(model.active('/groups/', '/groupsomething'), false);
});
test('direct-entry defaults include Events and exclude Friends', () => {
  assert.ok(model.defaults.some(item => item.href === '/events/'));
  assert.ok(!model.defaults.some(item => item.href.includes('friends')));
  assert.deepEqual(plain(model.clean(undefined)), []);
});
test('manifest includes the menu model before its controller and all files exist', () => {
  const root = path.join(__dirname, '..');
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
  const script = manifest.content_scripts[0];
  assert.ok(script.js.indexOf('src/sidebar-model.js') < script.js.indexOf('src/sidebar.js'));
  for (const file of [...script.js, ...script.css]) assert.ok(fs.existsSync(path.join(root, file)), file);
});
