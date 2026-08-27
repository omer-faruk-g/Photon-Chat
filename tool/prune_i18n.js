#!/usr/bin/env node
// Deletes i18n keys that no code path can reach. Every language switch
// translates the whole map, so dead entries are pure latency.
//
// Safe because the codebase has no computed key lookups: keys are referenced as
// .t('literal'), as literals inside a .t( ... ) argument list, or as
// _baseTr['literal']. The one exception is the language_* family, read via
// languageLabel(), which is preserved.
//
// Usage: node tool/prune_i18n.js [--apply]   (default is a dry run)

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const LIB = path.join(ROOT, 'lib');
const I18N = path.join(LIB, 'i18n.dart');
const KEEP_PREFIXES = ['language_'];
const apply = process.argv.includes('--apply');

function dartFiles(dir) {
  let out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out = out.concat(dartFiles(p));
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

const used = new Set();
for (const f of dartFiles(LIB)) {
  const src = fs.readFileSync(f, 'utf8');
  for (const m of src.matchAll(/\.t\(([^)]*)\)/g)) {
    for (const lit of m[1].matchAll(/'([A-Za-z_0-9]+)'/g)) used.add(lit[1]);
  }
  for (const m of src.matchAll(/_baseTr\['([A-Za-z_0-9]+)'\]/g)) used.add(m[1]);
}

const src = fs.readFileSync(I18N, 'utf8');
const lines = src.split('\n');
const removed = [];
const kept = [];

for (const line of lines) {
  const m = line.match(/^\s+'([A-Za-z_0-9]+)':/);
  if (!m) { kept.push(line); continue; }
  const key = m[1];
  const alive = used.has(key) || KEEP_PREFIXES.some((p) => key.startsWith(p));
  if (alive) kept.push(line);
  else removed.push(key);
}

console.log(`used: ${used.size}   removing: ${removed.length}`);
console.log(removed.join(', '));

if (!apply) {
  console.log('\ndry run — pass --apply to write');
  process.exit(0);
}
fs.writeFileSync(I18N, kept.join('\n'));
console.log(`\nwrote ${I18N}`);
