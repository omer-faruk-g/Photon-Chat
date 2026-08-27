#!/usr/bin/env node
// Static checks for the Flutter client. There is no Dart toolchain in the dev
// container, so this catches the specific bug classes that have actually broken
// releases before: missing i18n keys (renders the raw key on screen), duplicate
// keys in a const Map (compile error), `const` wrapping a runtime call (compile
// error), stray null bytes, and unbalanced delimiters.
//
// Usage: node tool/verify.js
// Exit 0 = clean, 1 = problems found (printed as file:line).

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const LIB = path.join(ROOT, 'lib');
const I18N = path.join(LIB, 'i18n.dart');

// Keys reachable only through computed lookups. Everything else must appear as
// a literal `.t('...')` call somewhere or it counts as dead.
const DYNAMIC_KEY_PREFIXES = ['language_'];

const problems = [];
const notes = [];
function fail(file, line, msg) {
  problems.push(`${path.relative(ROOT, file)}:${line}: ${msg}`);
}

function dartFiles(dir) {
  let out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out = out.concat(dartFiles(p));
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out.sort();
}

function lineOf(src, index) {
  return src.slice(0, index).split('\n').length;
}

// --- 1 & 2: i18n key definitions -------------------------------------------
const i18nSrc = fs.readFileSync(I18N, 'utf8');
const defined = new Map(); // key -> line
for (const m of i18nSrc.matchAll(/^\s+'([A-Za-z_0-9]+)':/gm)) {
  const line = lineOf(i18nSrc, m.index);
  if (defined.has(m[1])) {
    fail(I18N, line, `duplicate i18n key '${m[1]}' (first at line ${defined.get(m[1])}) — breaks the const Map`);
  } else {
    defined.set(m[1], line);
  }
}

// --- collect every literal key reference ------------------------------------
// Three shapes occur in this codebase and all three must count as "used",
// otherwise the dead-key sweep would delete a key that is actually rendered:
//   1. .t('key')                      — the common case
//   2. .t(\n  cond ? 'a' : 'b')       — argument on a following line
//   3. _baseTr['key']                 — direct map read inside i18n.dart
const files = dartFiles(LIB);
const used = new Map(); // key -> [ {file, line} ]
function markUsed(key, file, line) {
  if (!used.has(key)) used.set(key, []);
  used.get(key).push({ file, line });
}
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  // Shapes 1 and 2: take every string literal inside the .t( ... ) argument
  // list, so ternaries and line breaks are covered.
  for (const m of src.matchAll(/\.t\(([^)]*)\)/g)) {
    for (const lit of m[1].matchAll(/'([A-Za-z_0-9]+)'/g)) {
      markUsed(lit[1], f, lineOf(src, m.index));
    }
  }
  // Shape 3
  for (const m of src.matchAll(/_baseTr\['([A-Za-z_0-9]+)'\]/g)) {
    markUsed(m[1], f, lineOf(src, m.index));
  }
}

// 1. every used key must be defined
for (const [key, sites] of used) {
  if (!defined.has(key)) {
    for (const s of sites) fail(s.file, s.line, `i18n key '${key}' is referenced but never defined — renders the raw key (or a hardcoded fallback)`);
  }
}

// dead keys are reported, not failed (deleting them is a separate deliberate step)
const dead = [...defined.keys()].filter(
  (k) => !used.has(k) && !DYNAMIC_KEY_PREFIXES.some((p) => k.startsWith(p))
);
if (dead.length) notes.push(`${dead.length} unused i18n key(s): ${dead.slice(0, 12).join(', ')}${dead.length > 12 ? ', …' : ''}`);

// --- 3-6: per-file source checks --------------------------------------------
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');

  // 6. null bytes / lone surrogates from bad sed edits
  const nb = src.indexOf('\0');
  if (nb !== -1) fail(f, lineOf(src, nb), 'file contains a NUL byte');

  const lines = src.split('\n');
  lines.forEach((text, i) => {
    const ln = i + 1;

    // 3. `const` widget wrapping a runtime call — Dart rejects this.
    if (/\bconst\s+[A-Za-z_][A-Za-z0-9_]*\s*\([^)]*\b(?:AppLang\.instance\.t|FontSizeNotifier\.instance|DateTime\.now|PhotonColors\.)/.test(text)) {
      fail(f, ln, 'const constructor wraps a runtime expression — will not compile');
    }

    // 4. `const` string literal containing interpolation.
    if (/\bconst\b[^;]*'[^']*\$\{?[A-Za-z_]/.test(text) && !text.trimStart().startsWith('//')) {
      fail(f, ln, 'const with an interpolated string — will not compile');
    }
  });

  // 5. delimiter balance, ignoring strings and comments
  const bal = { '(': 0, '[': 0, '{': 0 };
  const close = { ')': '(', ']': '[', '}': '{' };
  let i = 0, inLine = false, inBlock = false, quote = null, raw = false;
  while (i < src.length) {
    const c = src[i], c2 = src[i + 1];
    if (inLine) { if (c === '\n') inLine = false; i++; continue; }
    if (inBlock) { if (c === '*' && c2 === '/') { inBlock = false; i += 2; continue; } i++; continue; }
    if (quote) {
      if (!raw && c === '\\') { i += 2; continue; }
      if (src.startsWith(quote, i)) { i += quote.length; quote = null; raw = false; continue; }
      i++; continue;
    }
    if (c === '/' && c2 === '/') { inLine = true; i += 2; continue; }
    if (c === '/' && c2 === '*') { inBlock = true; i += 2; continue; }
    if (c === 'r' && (c2 === "'" || c2 === '"')) { raw = true; quote = c2; i += 2; continue; }
    if (c === "'" || c === '"') {
      const triple = src.substr(i, 3);
      if (triple === "'''" || triple === '"""') { quote = triple; i += 3; continue; }
      quote = c; i++; continue;
    }
    if (c in bal) bal[c]++;
    else if (c in close) bal[close[c]]--;
    i++;
  }
  if (quote) fail(f, lines.length, `unterminated string literal (${quote})`);
  for (const [open, n] of Object.entries(bal)) {
    if (n !== 0) fail(f, lines.length, `unbalanced '${open}' — off by ${n}`);
  }
}

// --- 7: version consistency --------------------------------------------------
const pubspec = fs.readFileSync(path.join(ROOT, 'pubspec.yaml'), 'utf8');
const vm = pubspec.match(/^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)/m);
if (!vm) {
  problems.push('pubspec.yaml: could not parse version');
} else {
  const tag = `v${vm[1]}`;
  const notesPy = fs.readFileSync(path.join(ROOT, '.github/scripts/release_notes.py'), 'utf8');
  if (!notesPy.includes(`'${tag}': (`)) problems.push(`release_notes.py: no CHANGELOGS entry for ${tag}`);
  const huawei = notesPy.match(/^HUAWEI_VERSIONS = \{([^}]*)\}/m);
  const installer = notesPy.match(/^INSTALLER_VERSIONS = \{([^}]*)\}/m);
  if (huawei && !huawei[1].includes(`'${tag}'`)) problems.push(`release_notes.py: ${tag} missing from HUAWEI_VERSIONS`);
  if (installer && !installer[1].includes(`'${tag}'`)) problems.push(`release_notes.py: ${tag} missing from INSTALLER_VERSIONS`);
}

// --- report ------------------------------------------------------------------
console.log(`i18n: ${defined.size} defined, ${used.size} used, ${dead.length} dead`);
console.log(`scanned ${files.length} dart files`);
for (const n of notes) console.log(`note: ${n}`);
if (problems.length) {
  console.error(`\n${problems.length} PROBLEM(S):`);
  for (const p of problems) console.error('  ' + p);
  process.exit(1);
}
console.log('\nOK — no problems found.');
