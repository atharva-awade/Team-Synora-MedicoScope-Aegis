#!/usr/bin/env node
'use strict';
/**
 * GOLDEN CORPUS REGRESSION + DETERMINISM LOCK.
 *
 * A gate nobody tests is a decoration. This harness is the evidence that the
 * gate does what it claims, and it runs three orthogonal proofs:
 *
 *   1. BEHAVIOUR   -- every labelled fixture reaches its expected verdict, and
 *                     the specific checks it was written to trip actually trip.
 *                     This is a confusion matrix over the CHECKER, not the
 *                     content: it catches a rule that silently stopped firing.
 *
 *   2. DETERMINISM -- each fixture is evaluated N times and every run must
 *                     return the byte-identical certificate id. "Repeatable" is
 *                     asserted here or it is marketing.
 *
 *   3. HASH LOCK   -- certificate ids are committed to CERTIFICATES.lock.json.
 *                     Any change to the engine, a pack, or a fixture that moves
 *                     a certificate FAILS the build until a human re-locks with
 *                     `--update`. This is what stops silent rule drift: you
 *                     cannot quietly loosen the gate and keep a green CI.
 *
 * Usage:
 *   node harness/verify.js            # verify (CI mode, exits non-zero on fail)
 *   node harness/verify.js --update   # re-lock certificate ids after an
 *                                     # intentional rule change
 *   node harness/verify.js --json     # machine-readable report
 */
const fs = require('fs');
const path = require('path');
const qg = require('../index');

const CORPUS_DIR = path.join(__dirname, '..', 'corpus');
const LOCK_FILE = path.join(CORPUS_DIR, 'CERTIFICATES.lock.json');
const REPEATS = 12;

const argv = process.argv.slice(2);
const UPDATE = argv.indexOf('--update') >= 0;
const JSON_OUT = argv.indexOf('--json') >= 0;

function loadFixtures() {
  return fs.readdirSync(CORPUS_DIR)
    .filter((f) => f.endsWith('.json') && !f.startsWith('CERTIFICATES') && !f.startsWith('PARITY'))
    .sort()
    .map((f) => JSON.parse(fs.readFileSync(path.join(CORPUS_DIR, f), 'utf8')));
}

function main() {
  const fixtures = loadFixtures();
  const lock = fs.existsSync(LOCK_FILE) ? JSON.parse(fs.readFileSync(LOCK_FILE, 'utf8')) : { certificates: {} };
  const nextLock = { engineVersion: qg.ENGINE_VERSION, packs: {}, certificates: {} };
  for (const id of qg.packIds()) {
    const p = qg.pack(id);
    nextLock.packs[id] = { packVersion: p.packVersion, packDigest: p.packDigest };
  }

  const rows = [];
  let failures = 0;

  for (const fx of fixtures) {
    const pack = qg.pack(fx.pack || 'medical');
    const first = qg.evaluate({ content: fx.content, pack, profile: fx.profile });

    // --- 2. determinism -------------------------------------------------
    let stable = true;
    for (let i = 1; i < REPEATS; i++) {
      const again = qg.evaluate({ content: fx.content, pack, profile: fx.profile });
      if (again.verdictDigest !== first.verdictDigest) { stable = false; break; }
    }

    // --- 1. behaviour ---------------------------------------------------
    const problems = [];
    const exp = fx.expect || {};
    if (exp.status && first.status !== exp.status) {
      problems.push(`status ${first.status} != expected ${exp.status}`);
    }
    for (const id of exp.mustBlock || []) {
      if (first.blocking.indexOf(id) < 0) problems.push(`expected BLOCKING check ${id} did not block`);
    }
    const failed = new Set(first.checks.filter((c) => !c.ok).map((c) => c.id));
    for (const id of exp.mustFail || []) {
      if (!failed.has(id)) problems.push(`expected check ${id} to fail, it passed`);
    }
    for (const id of exp.mustPass || []) {
      if (failed.has(id)) problems.push(`expected check ${id} to pass, it failed`);
    }
    // A PASS fixture must not fail anything it did not declare.
    if (exp.status === 'PASS') {
      const declared = new Set([].concat(exp.mustFail || [], exp.mustBlock || []));
      for (const id of failed) {
        if (!declared.has(id)) problems.push(`unexpected failure on a PASS fixture: ${id}`);
      }
    }
    if (!stable) problems.push(`NON-DETERMINISTIC across ${REPEATS} runs`);

    // --- 3. hash lock ---------------------------------------------------
    const locked = lock.certificates && lock.certificates[fx.id];
    let lockState = 'new';
    if (locked) {
      if (locked.certificateId === first.certificateId && locked.verdictDigest === first.verdictDigest) {
        lockState = 'match';
      } else {
        lockState = 'DRIFT';
        if (!UPDATE) {
          problems.push(`certificate drift: locked ${locked.certificateId} -> now ${first.certificateId}`);
        }
      }
    }

    nextLock.certificates[fx.id] = {
      certificateId: first.certificateId,
      verdictDigest: first.verdictDigest,
      contentDigest: first.contentDigest,
      status: first.status,
      score: first.score,
      pack: pack.packId + '@' + pack.packVersion,
      profile: first.profile,
    };

    if (problems.length) failures++;
    rows.push({
      id: fx.id, note: fx.note, pack: pack.packId, profile: first.profile,
      status: first.status, score: first.score, certificateId: first.certificateId,
      deterministic: stable, lockState, problems,
      blocking: first.blocking, grounding: first.metrics.groundingCoverage, fkGrade: first.metrics.fkGrade,
    });
  }

  if (UPDATE) {
    fs.writeFileSync(LOCK_FILE, JSON.stringify(nextLock, null, 2) + '\n');
  }

  if (JSON_OUT) {
    console.log(JSON.stringify({ ok: failures === 0, fixtures: rows.length, failures, rows }, null, 2));
    process.exit(failures === 0 ? 0 : 1);
  }

  // ---- report --------------------------------------------------------
  const W = (s, n) => String(s).padEnd(n).slice(0, n);
  console.log('\nAEGIS QUALITY GATE -- GOLDEN CORPUS VERIFICATION');
  console.log(`engine ${qg.ENGINE_VERSION}   packs: ` +
    qg.packIds().map((i) => `${i}@${qg.pack(i).packVersion}#${qg.pack(i).packDigest.slice(0, 8)}`).join('  '));
  console.log(`determinism: ${REPEATS} repeat evaluations per fixture\n`);
  console.log(W('FIXTURE', 32) + W('PACK', 9) + W('PROFILE', 19) + W('STATUS', 7) +
    W('SCORE', 7) + W('CERTIFICATE', 13) + W('DET', 5) + W('LOCK', 7) + 'RESULT');
  console.log('-'.repeat(120));
  for (const r of rows) {
    console.log(
      W(r.id, 32) + W(r.pack, 9) + W(r.profile, 19) + W(r.status, 7) +
      W(r.score.toFixed(3), 7) + W(r.certificateId, 13) +
      W(r.deterministic ? 'ok' : 'NO', 5) + W(r.lockState, 7) +
      (r.problems.length ? 'FAIL' : 'pass')
    );
    for (const p of r.problems) console.log('    ! ' + p);
  }

  const byStatus = rows.reduce((a, r) => { a[r.status] = (a[r.status] || 0) + 1; return a; }, {});
  console.log('-'.repeat(120));
  console.log(`fixtures: ${rows.length}   ` +
    Object.keys(byStatus).sort().map((k) => `${k}=${byStatus[k]}`).join('  ') +
    `   deterministic: ${rows.filter((r) => r.deterministic).length}/${rows.length}` +
    `   locked: ${rows.filter((r) => r.lockState === 'match').length}/${rows.length}`);
  if (UPDATE) console.log(`\ncertificate lock re-written: ${path.relative(process.cwd(), LOCK_FILE)}`);
  console.log(failures === 0 ? '\nRESULT: all fixtures behave as specified.\n'
    : `\nRESULT: ${failures} fixture(s) FAILED.\n`);
  process.exit(failures === 0 ? 0 : 1);
}

main();
