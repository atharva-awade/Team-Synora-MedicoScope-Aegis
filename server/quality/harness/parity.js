#!/usr/bin/env node
'use strict';
/**
 * CROSS-RUNTIME PARITY VECTORS.
 *
 * The gate runs in two places: Node on the server (authoritative) and Dart in
 * the Flutter app (instant feedback while a clinician types). Two
 * implementations of the same rules is normally where "repeatable" quietly
 * dies -- the phone says 92 and the server says 88, and nobody notices until a
 * certificate cannot be reproduced.
 *
 * So parity is not a code-review promise, it is a test. This script emits the
 * Node engine's exact output for every fixture; the Dart test
 * (test/quality_gate_parity_test.dart) reads the same file and asserts the Dart
 * engine reproduces it BYTE FOR BYTE, down to the certificate id.
 *
 * PARITY_UNITS.json carries lower-level vectors too -- canonical JSON strings,
 * digests, syllable counts, readability numbers, claim extraction -- so that a
 * Dart failure points at the function that diverged instead of just saying
 * "hash mismatch" and leaving you to guess.
 *
 * Usage: node harness/parity.js            (writes both vector files)
 *        node harness/parity.js --check    (fails if regenerating would change them)
 */
const fs = require('fs');
const path = require('path');
const qg = require('../index');

const CORPUS_DIR = path.join(__dirname, '..', 'corpus');
const VECTORS = path.join(CORPUS_DIR, 'PARITY_VECTORS.json');
const UNITS = path.join(CORPUS_DIR, 'PARITY_UNITS.json');
const CHECK = process.argv.indexOf('--check') >= 0;

function fixtures() {
  return fs.readdirSync(CORPUS_DIR)
    .filter((f) => f.endsWith('.json') && !f.startsWith('CERTIFICATES') && !f.startsWith('PARITY'))
    .sort()
    .map((f) => JSON.parse(fs.readFileSync(path.join(CORPUS_DIR, f), 'utf8')));
}

// ---------------------------------------------------------------- end-to-end
function buildVectors() {
  const out = {
    generatedBy: 'server/quality/harness/parity.js',
    engineVersion: qg.ENGINE_VERSION,
    packs: {},
    cases: [],
  };
  for (const id of qg.packIds()) {
    const p = qg.pack(id);
    out.packs[id] = { packVersion: p.packVersion, packDigest: p.packDigest, checkCount: p.checks.length };
  }
  for (const fx of fixtures()) {
    const pack = qg.pack(fx.pack || 'medical');
    const v = qg.evaluate({ content: fx.content, pack, profile: fx.profile });
    out.cases.push({
      id: fx.id,
      pack: pack.packId,
      profile: v.profile,
      contentDigest: v.contentDigest,
      packDigest: v.packDigest,
      verdictDigest: v.verdictDigest,
      certificateId: v.certificateId,
      status: v.status,
      score: v.score,
      dimensions: v.dimensions.map((d) => ({ id: d.id, score: d.score })),
      metrics: v.metrics,
      checks: v.checks.map((c) => ({ id: c.id, ok: c.ok, severity: c.severity })),
      blocking: v.blocking,
      claims: v.claims.map((c) => ({ raw: c.raw, value: c.value, unit: c.unit, kind: c.kind, boundTo: c.boundTo, matchKind: c.matchKind })),
    });
  }
  return out;
}

// ---------------------------------------------------------------- unit level
function buildUnits() {
  const { canonical, digest, shortId, score4 } = qg.canonical;
  const T = qg.text;
  const C = qg.claims;

  const canonicalCases = [
    null, true, false, 0, -0, 1, 1.5, 0.1 + 0.2, 1e-7, -3.25,
    'plain', 'quote"inside', 'tab\tnewline\n',
    [1, 'a', null, [2, 3]],
    { b: 1, a: 2 },
    { z: { y: [1, 2] }, a: 'x', n: null },
    { score: 0.8573494, arr: [0.1, 0.2, 0.3] },
  ];

  const textCases = [
    '',
    'Short line.',
    'Your blood pressure was estimated at 128/84 mmHg. That is a little high. See a doctor within 7 days.',
    'Photoplethysmographic estimation demonstrated prehypertensive stratification necessitating confirmatory oscillometric sphygmomanometry.',
    'BP was 128.4 mmHg. e.g. this is one. Dr. Rao advised follow-up. Two!',
    'Line one\r\nLine two  \n\n  Line three   ',
  ];

  const syllableWords = ['a', 'the', 'apple', 'estimated', 'haemoglobin', 'photoplethysmography',
    'blood', 'pressure', 'anaemia', 'diagnosis', 'screening', 'rhythm', 'played', 'cared', 'yellow'];

  const claimCases = [
    {
      text: 'Estimated at 128/84 mmHg with a heart rate of around 72 bpm. Normal sits below 120 over 80. HbA1c is 6.8%. Haemoglobin of 9.2 g/dL. Follow up within 14 days.',
      labels: ['haemoglobin', 'hemoglobin', 'hba1c'],
    },
    {
      text: 'Spend was 41200 usd against a budget of 45000 usd. Ticket volume fell to 318 tickets.',
      labels: ['ticket volume', 'tickets'],
    },
  ];

  return {
    generatedBy: 'server/quality/harness/parity.js',
    engineVersion: qg.ENGINE_VERSION,
    canonical: canonicalCases.map((v) => ({
      input: v === undefined ? null : v,
      canonical: canonical(v),
      digest: digest(v),
      shortId: shortId(digest(v)),
    })),
    score4: [0.857349, 0.8573, 1, 0, 0.99995, 0.123456789].map((x) => ({ input: x, output: score4(x) })),
    syllables: syllableWords.map((w) => ({ word: w, syllables: T.syllables(w) })),
    sentences: textCases.map((t) => ({ text: t, sentences: T.sentences(t) })),
    readability: textCases.map((t) => ({ text: t, metrics: T.readability(t), band: T.gradeBand(T.readability(t).fkGrade) })),
    normalizeText: textCases.map((t) => ({ text: t, normalized: T.normalizeText(t) })),
    claims: claimCases.map((cc) => ({
      text: cc.text,
      labels: cc.labels,
      extracted: C.extractClaims(cc.text, { bareNumberLabels: cc.labels }).map((c) => ({
        value: c.value, unit: c.unit, role: c.role, kind: c.kind, raw: c.raw, offset: c.offset,
      })),
    })),
  };
}

function writeOrCheck(file, obj) {
  const next = JSON.stringify(obj, null, 2) + '\n';
  if (CHECK) {
    const cur = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
    if (cur !== next) {
      console.error(`PARITY DRIFT: ${path.relative(process.cwd(), file)} is stale. Run: npm run gate:parity`);
      return false;
    }
    return true;
  }
  fs.writeFileSync(file, next);
  return true;
}

const vectors = buildVectors();
const units = buildUnits();
const ok = writeOrCheck(VECTORS, vectors) && writeOrCheck(UNITS, units);

console.log('\nAEGIS QUALITY GATE -- CROSS-RUNTIME PARITY VECTORS');
console.log(`engine ${qg.ENGINE_VERSION}`);
console.log(`end-to-end cases : ${vectors.cases.length}`);
console.log(`check assertions : ${vectors.cases.reduce((a, c) => a + c.checks.length, 0)}`);
console.log(`unit vectors     : canonical ${units.canonical.length}, syllables ${units.syllables.length}, ` +
  `readability ${units.readability.length}, claims ${units.claims.length}`);
console.log(CHECK ? (ok ? 'vectors are current.' : 'VECTORS ARE STALE.')
  : `written:\n  ${path.relative(process.cwd(), VECTORS)}\n  ${path.relative(process.cwd(), UNITS)}`);
console.log('the Dart engine must reproduce every value above byte-for-byte (test/quality_gate_parity_test.dart)\n');
process.exit(ok ? 0 : 1);
