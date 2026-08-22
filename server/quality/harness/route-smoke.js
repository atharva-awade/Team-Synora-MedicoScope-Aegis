#!/usr/bin/env node
'use strict';
/**
 * ROUTE SMOKE TEST for the DB-free half of the Quality Gate API.
 *
 * /evaluate, /packs, /rewrite/check and /critique/compile are pure -- no Mongo,
 * no clock in the verdict -- so they can be exercised end to end in CI with a
 * stubbed auth middleware and no database. That covers the surface a hackathon
 * judge is most likely to poke at, and it means the API contract is tested
 * rather than described.
 *
 * The persisting routes (/certify, /finalize, /verify) need a live Mongo and are
 * covered by the app's own integration setup; the enforcement LOGIC they rely on
 * is the same pure evaluate() proven by the golden corpus.
 *
 * Usage: node harness/route-smoke.js
 */
const http = require('http');
const path = require('path');
const Module = require('module');

// Stub the auth middleware BEFORE the route module is required, so the routes
// under test are the real ones and only the identity is faked.
const AUTH_PATH = path.join(__dirname, '..', '..', 'src', 'middleware', 'auth.js');
const origResolve = Module._resolveFilename;
const origLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (parent && /routes[\\/]quality-gate\.js$/.test(parent.filename) && request === '../middleware/auth') {
    return function stubAuth(req, res, next) { req.user = { _id: 'stub-user', role: 'doctor' }; next(); };
  }
  return origLoad.apply(this, arguments);
};

const express = require('express');
const router = require('../../src/routes/quality-gate');

const app = express();
app.use(express.json({ limit: '2mb' }));
app.use('/api/quality-gate', router);

const BP_EV = [{ toolId: 'ppg_bp', modality: 'ppg', fidelity: 'heuristic', label: 'systolic', value: 128,
  unit: 'mmHg', provenance: { source: 'camera_ppg_v2' },
  findings: [{ label: 'diastolic', value: 84, unit: 'mmHg' }, { label: 'heart_rate', value: 72, unit: 'bpm' }] }];

const GOOD = {
  title: 'Raised blood pressure estimate', category: 'hypertension', riskLevel: 'high',
  score: 0.71, confidence: 0.62,
  body: 'Your blood pressure was estimated at 128/84 mmHg from the camera pulse scan, and your resting heart ' +
        'rate was around 72 bpm. This is a screening signal, not a diagnosis. A normal range sits below 120 over ' +
        '80, so this reading suggests high blood pressure (raised pressure in your arteries). Please see a doctor ' +
        'within 7 days and ask for a cuff measurement to confirm it.',
  recommendations: ['Book a cuff blood pressure check with your doctor within 7 days.',
                    'Repeat this scan each morning for a week and record the values.'],
  disclaimer: 'Screening-grade estimate. Requires clinical confirmation.', evidence: BP_EV,
};

function req(method, urlPath, body) {
  return new Promise((resolve, reject) => {
    const payload = body ? Buffer.from(JSON.stringify(body)) : null;
    const r = http.request({
      host: '127.0.0.1', port: server.address().port, path: urlPath, method,
      headers: Object.assign({ Authorization: 'Bearer stub' },
        payload ? { 'Content-Type': 'application/json', 'Content-Length': payload.length } : {}),
    }, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => {
        let parsed = null;
        try { parsed = JSON.parse(data); } catch (_) { parsed = data; }
        resolve({ status: res.statusCode, body: parsed });
      });
    });
    r.on('error', reject);
    if (payload) r.write(payload);
    r.end();
  });
}

const results = [];
function check(name, cond, detail) {
  results.push({ name, ok: !!cond, detail: detail || '' });
}

const server = app.listen(0, async () => {
  try {
    // 1. policy catalogue is published
    const packs = await req('GET', '/api/quality-gate/packs');
    check('GET /packs returns 200', packs.status === 200, 'status ' + packs.status);
    check('GET /packs publishes both packs', (packs.body.packs || []).length === 2,
      'packs ' + (packs.body.packs || []).map((p) => p.packId).join(','));
    check('GET /packs publishes the predicate registry',
      ((packs.body.packs || [])[0] || {}).predicateRegistry &&
      packs.body.packs[0].predicateRegistry.length >= 25);

    // 2. a clean report passes
    const good = await req('POST', '/api/quality-gate/evaluate', { content: GOOD, profile: 'patient_report' });
    check('POST /evaluate PASSes a clean report', good.body.verdict && good.body.verdict.status === 'PASS',
      good.body.verdict && good.body.verdict.status);

    // 3. the same request is byte-identical the second time
    const again = await req('POST', '/api/quality-gate/evaluate', { content: GOOD, profile: 'patient_report' });
    check('POST /evaluate is reproducible over HTTP',
      again.body.verdict.certificateId === good.body.verdict.certificateId,
      good.body.verdict.certificateId + ' vs ' + again.body.verdict.certificateId);

    // 4. an invented measurement blocks
    const bad = JSON.parse(JSON.stringify(GOOD));
    bad.body += ' Your haemoglobin is 7.4 g/dL, which is low.';
    const blocked = await req('POST', '/api/quality-gate/evaluate', { content: bad, profile: 'patient_report' });
    check('POST /evaluate BLOCKs an invented measurement', blocked.body.verdict.status === 'BLOCK');
    check('the blocking check is the grounding rule',
      blocked.body.verdict.blocking.indexOf('GRD_NO_UNGROUNDED_CLAIMS') >= 0,
      blocked.body.verdict.blocking.join(','));

    // 5. missing content is a 400, not a 500
    const empty = await req('POST', '/api/quality-gate/evaluate', {});
    check('POST /evaluate rejects a missing body with 400', empty.status === 400, 'status ' + empty.status);

    // 6. the rewrite contract rejects a fact-altering "fix"
    const cheat = JSON.parse(JSON.stringify(GOOD));
    cheat.body = cheat.body.replace('128/84', '118/78');
    const rw = await req('POST', '/api/quality-gate/rewrite/check',
      { before: GOOD, after: cheat, profile: 'patient_report' });
    check('POST /rewrite/check REJECTS a number-changing rewrite', rw.body.accepted === false);
    check('rejection names the drift',
      (rw.body.contract.violations || []).some((v) => v.type === 'NUMERIC_CLAIM_DRIFT'),
      JSON.stringify((rw.body.contract.violations || []).map((v) => v.type)));

    // 7. a prose-only rewrite is allowed through and scored
    const honest = JSON.parse(JSON.stringify(GOOD));
    honest.body = honest.body.replace('so this reading suggests', 'which means this reading suggests');
    const rw2 = await req('POST', '/api/quality-gate/rewrite/check',
      { before: GOOD, after: honest, profile: 'patient_report' });
    check('POST /rewrite/check ACCEPTS a prose-only rewrite', rw2.body.accepted === true,
      JSON.stringify(rw2.body.contract && rw2.body.contract.violations));

    // 8. the critic compiler refuses a malicious proposal and keeps a valid one
    const crit = await req('POST', '/api/quality-gate/critique/compile', {
      content: GOOD, profile: 'patient_report',
      proposals: [
        { predicate: 'readabilityGradeAtMost', args: { max: 6 }, dimension: 'readability', severity: 'minor', rationale: 'low-literacy cohort' },
        { predicate: 'rm -rf /', args: {}, rationale: 'malicious' },
        { predicate: 'piiAbsent', args: { patterns: ['(a+)+b'] }, dimension: 'safety', severity: 'major', rationale: 'redos' },
      ],
    });
    check('POST /critique/compile accepts the one valid assertion', (crit.body.accepted || []).length === 1);
    check('POST /critique/compile rejects the injection and the ReDoS', (crit.body.rejected || []).length === 2,
      JSON.stringify((crit.body.rejected || []).map((r) => r.reason)));
    check('advisory findings are marked non-authoritative',
      (crit.body.findings || []).every((f) => f.authority === 'advisory_only'));

    // 9. advisory findings on /evaluate never move the verdict
    const withAdv = await req('POST', '/api/quality-gate/evaluate', {
      content: GOOD, profile: 'patient_report',
      proposals: [{ predicate: 'readabilityGradeAtMost', args: { max: 1 }, dimension: 'readability', severity: 'major', rationale: 'impossible bar' }],
    });
    check('a failing advisory assertion does not change the verdict',
      withAdv.body.verdict.status === 'PASS' &&
      withAdv.body.verdict.certificateId === good.body.verdict.certificateId &&
      withAdv.body.advisory.findings.some((f) => !f.ok),
      withAdv.body.verdict.status);

  } catch (err) {
    check('harness ran without throwing', false, String(err && err.stack || err));
  } finally {
    server.close();
    const W = (s, n) => String(s).padEnd(n).slice(0, n);
    console.log('\nAEGIS QUALITY GATE -- API ROUTE SMOKE TEST\n');
    let bad = 0;
    for (const r of results) {
      if (!r.ok) bad++;
      console.log('  ' + W(r.ok ? 'pass' : 'FAIL', 6) + r.name + (r.detail && !r.ok ? '   [' + r.detail + ']' : ''));
    }
    console.log(`\n${results.length - bad}/${results.length} assertions passed.`);
    console.log(bad === 0 ? 'RESULT: the API behaves as documented.\n' : `RESULT: FAILED (${bad}).\n`);
    process.exit(bad === 0 ? 0 : 1);
  }
});
