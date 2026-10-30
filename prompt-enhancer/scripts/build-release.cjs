// Dependency-free, cross-platform release builder using Node's standard library.
// ZIP entries use DEFLATE, CRC32, UTF-8 names and a fixed timestamp for reproducibility.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const runtimeFiles = [
  'manifest.json',
  'icons/icon16.png', 'icons/icon32.png', 'icons/icon48.png', 'icons/icon128.png',
  'src/settings.js', 'src/editor.js', 'src/chat-export.js', 'src/content.js', 'src/styles.css',
  'src/background.js', 'src/llama-api.js', 'src/prompt-template.js',
  'src/options.html', 'src/options.js', 'src/options.css',
  'src/popup.html', 'src/popup.js', 'src/popup.css',
  'src/setup.html', 'src/setup.css'
];
function crc32(data) {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function validateReferences(files) {
  const requireFile = name => assert.ok(files.has(name), `Missing packaged reference: ${name}`);
  requireFile('manifest.json');
  const manifest = JSON.parse(files.get('manifest.json').toString('utf8'));
  assert.equal(manifest.manifest_version, 3);
  assert.match(manifest.version, /^\d+\.\d+\.\d+(?:\.\d+)?$/);
  const refs = [
    manifest.background.service_worker, manifest.options_page, manifest.action.default_popup,
    ...Object.values(manifest.icons), ...Object.values(manifest.action.default_icon),
    ...manifest.content_scripts.flatMap(item => [...item.js, ...(item.css || [])]),
    ...manifest.web_accessible_resources.flatMap(item => item.resources)
  ];
  refs.forEach(requireFile);
  function localRef(from, reference) {
    if (/^(?:https?:|mailto:|#)/.test(reference)) return;
    assert.ok(!reference.includes('\\'), `Invalid separator: ${reference}`);
    const name = path.posix.normalize(path.posix.join(path.posix.dirname(from), reference.split(/[?#]/)[0]));
    assert.ok(!name.startsWith('../') && !path.posix.isAbsolute(name), `Unsafe reference: ${name}`);
    requireFile(name);
  }
  for (const [name, data] of files) {
    if (name.endsWith('.html')) {
      const text = data.toString('utf8');
      for (const match of text.matchAll(/<(script|link|img|a)\b[^>]*?\b(?:src|href)="([^"]+)"/g)) {
        if (match[1] !== 'a') assert.ok(!/^[a-z]+:/i.test(match[2]), `Remote runtime asset: ${match[2]}`);
        localRef(name, match[2]);
      }
    }
    if (name.endsWith('.js')) {
      const text = data.toString('utf8');
      for (const call of text.matchAll(/importScripts\(([^)]+)\)/g)) {
        for (const ref of call[1].matchAll(/['"]([^'"]+)['"]/g)) localRef(name, ref[1]);
      }
      for (const ref of text.matchAll(/runtime\.getURL\(['"]([^'"]+)['"]\)/g)) requireFile(ref[1]);
    }
  }
  for (const [size, name] of Object.entries(manifest.icons)) {
    const data = files.get(name);
    assert.equal(data.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
    assert.equal(data.readUInt32BE(16), Number(size));
    assert.equal(data.readUInt32BE(20), Number(size));
  }
  return manifest;
}
function buildZip(files) {
  const localParts = [], centralParts = [];
  let offset = 0;
  for (const [name, data] of files) {
    const filename = Buffer.from(name, 'utf8'), compressed = zlib.deflateRawSync(data, { level: 9 });
    const crc = crc32(data), local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x800, 6);
    local.writeUInt16LE(8, 8);
    local.writeUInt16LE(33, 12); // 1980-01-01
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(filename.length, 26);
    localParts.push(local, filename, compressed);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    local.copy(central, 6, 4, 30);
    central.writeUInt32LE(offset, 42);
    centralParts.push(central, filename);
    offset += local.length + filename.length + compressed.length;
  }
  const central = Buffer.concat(centralParts), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(files.size, 8);
  end.writeUInt16LE(files.size, 10);
  end.writeUInt32LE(central.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...localParts, central, end]);
}
function validateZip(zip) {
  const end = zip.length - 22;
  assert.equal(zip.readUInt32LE(end), 0x06054b50);
  const count = zip.readUInt16LE(end + 10), files = new Map();
  let cursor = zip.readUInt32LE(end + 16);
  const centralStart = cursor;
  for (let index = 0; index < count; index++) {
    assert.equal(zip.readUInt32LE(cursor), 0x02014b50);
    assert.equal(zip.readUInt16LE(cursor + 10), 8);
    const length = zip.readUInt32LE(cursor + 20), size = zip.readUInt32LE(cursor + 24);
    assert.ok(size < 5 * 1024 * 1024, 'Unexpectedly large runtime file');
    const nameLength = zip.readUInt16LE(cursor + 28), extra = zip.readUInt16LE(cursor + 30);
    const comment = zip.readUInt16LE(cursor + 32), offset = zip.readUInt32LE(cursor + 42);
    const name = zip.subarray(cursor + 46, cursor + 46 + nameLength).toString('utf8');
    assert.ok(runtimeFiles.includes(name) && !files.has(name), `Unexpected or duplicate entry: ${name}`);
    assert.equal(zip.readUInt32LE(offset), 0x04034b50);
    assert.equal(zip.readUInt32LE(offset + 18), length);
    assert.equal(zip.readUInt32LE(offset + 22), size);
    const localNameLength = zip.readUInt16LE(offset + 26), localExtra = zip.readUInt16LE(offset + 28);
    assert.equal(zip.subarray(offset + 30, offset + 30 + localNameLength).toString('utf8'), name);
    const start = offset + 30 + localNameLength + localExtra;
    assert.ok(start + length <= centralStart);
    const data = zlib.inflateRawSync(zip.subarray(start, start + length), { maxOutputLength: 5 * 1024 * 1024 });
    assert.equal(data.length, size);
    assert.equal(crc32(data), zip.readUInt32LE(cursor + 16));
    assert.equal(crc32(data), zip.readUInt32LE(offset + 14));
    files.set(name, data);
    cursor += 46 + nameLength + extra + comment;
  }
  assert.equal(cursor, end);
  assert.equal(zip.readUInt32LE(end + 12), end - centralStart);
  assert.equal(files.size, runtimeFiles.length);
  validateReferences(files);
  return files;
}
if (require.main === module) {
  const files = new Map(runtimeFiles.map(name => [name, fs.readFileSync(path.join(root, name))]));
  const manifest = validateReferences(files);
  const destination = path.join(root, 'release', `local-prompt-enhancer-${manifest.version}.zip`);
  if (!process.argv.includes('--check')) {
    const zip = buildZip(files);
    validateZip(zip);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, zip);
  }
  const zip = fs.readFileSync(destination), packaged = validateZip(zip);
  for (const [name, data] of files) assert.ok(data.equals(packaged.get(name)), `Outdated packaged file: ${name}`);
  console.log(JSON.stringify({
    file: destination, version: manifest.version, entries: packaged.size,
    bytes: zip.length, sha256: crypto.createHash('sha256').update(zip).digest('hex'),
    validated: true
  }, null, 2));
}
module.exports = { runtimeFiles, validateReferences, buildZip, validateZip };
