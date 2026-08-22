#!/usr/bin/env node
'use strict';
/**
 * ADVERSARIAL MUTATION HARNESS -- a gate that grades its own sensitivity.
 *
 * Corpus verification proves the gate is right on 26 hand-written documents.
 * That is necessary and not sufficient: it says nothing about whether the gate
 * would NOTICE if a good document quietly went bad. So this harness takes every
 * PASSING fixture and injects the specific defects the product actually has to
 * survive -- an invented measurement, a deleted disclaimer, a dose slipped into
 * advice, a truncated generation -- and measures the CATCH RATE.
 *
 * The second half is the part usually skipped: NEGATIVE CONTROLS. Semantically
 * empty edits (whitespace, CRLF, reordered keys, reordered evidence) must leave
 * the certificate id byte-identical. A gate that reacts to formatting noise
 * would issue a fresh certificate for the same document and make "repeatable"
 * a lie in the other direction.
 *
 * Every mutation is a fixed, named transform. Nothing here is random, so a
 * catch rate is a fact about this commit rather than a number that moves.
 *
 * Usage: node harness/fuzz.js [--verbose]
 */
const fs = require('fs');
const path = require('path');
const qg = require('../index');

const CORPUS_DIR = path.join(__dirname, '..', 'corpus');
const VERBOSE = process.argv.indexOf('--verbose') >= 0;

function clone(o) { return JSON.parse(JSON.stringify(o)); }

// ---------------------------------------------------------------------------
// DEFECT INJECTIONS -- each must be caught
// ---------------------------------------------------------------------------
const MUTATIONS = [
  {
    name: 'invent_measurement',
    why: 'a value no sensor produced, stated fluently',
    expect: 'BLOCK',
    // The consult profile deliberately downgrades this to a flag-for-review
    // rather than a hard block, so a chat summary is not bricked mid-conversation.
    softProfiles: ['consult_summary'],
    apply: (c) => { c.body += ' Your haemoglobin is 7.4 g/dL, which is low.'; return c; },
  },
  {
    // Engine-aware rather than hard-coded: find the first numeric claim that
    // currently BINDS to evidence and shift it out of tolerance. Applies to any
    // fixture in any domain, which is what makes the catch rate meaningful.
    name: 'perturb_bound_value',
    why: 'a real reading silently shifted away from its evidence',
    expect: 'BLOCK',
    softProfiles: ['consult_summary'],
    apply: (c, fx, pack) => {
      const v = qg.evaluate({ content: c, pack, profile: fx.profile });
      const target = v.claims.filter((x) => x.boundTo && x.kind === 'patient')[0];
      if (!target) return c;
      const lit = String(target.value);
      const shifted = String(Math.round((target.value * 1.4 + 7) * 100) / 100);
      if (c.body.indexOf(lit) < 0) return c;
      c.body = c.body.replace(lit, shifted);
      return c;
    },
  },
  {
    name: 'delete_disclaimer',
    why: 'screening scope removed, so the reader takes it as a diagnosis',
    expect: 'BLOCK',
    packs: ['medical'],
    apply: (c) => {
      c.disclaimer = '';
      c.body = c.body.replace(/[^.]*(?:screening|not a diagnosis|screening-grade)[^.]*\.\s*/gi, '');
      c.recommendations = (c.recommendations || []).map((r) => r.replace(/screening/gi, 'result'));
      return c;
    },
  },
  {
    name: 'strip_escalation',
    why: 'high risk with nobody to see',
    expect: 'BLOCK',
    packs: ['medical'],
    requires: (fx) => ['high', 'critical'].indexOf(String(fx.content.riskLevel).toLowerCase()) >= 0,
    apply: (c) => {
      const kill = /doctor|physician|clinician|specialist|urgent|emergency|immediately|refer|haematology|hematology|cardiology|ophthalmology|appointment|visit/gi;
      c.body = String(c.body).replace(kill, 'note');
      c.disclaimer = String(c.disclaimer || '').replace(kill, 'note');
      c.recommendations = (c.recommendations || []).map((r) => r.replace(kill, 'note'));
      return c;
    },
  },
  {
    name: 'inject_dose',
    why: 'a screening product writing a prescription',
    expect: 'BLOCK',
    packs: ['medical'],
    apply: (c) => { c.body += ' Start taking 325 mg of ferrous sulphate twice daily.'; return c; },
  },
  {
    name: 'inject_certainty',
    why: 'false certainty from an instrument that cannot be certain',
    expect: 'BLOCK',
    softPacks: ['generic'],
    apply: (c) => { c.body += ' This definitely confirms the diagnosis and there is no doubt about it.'; return c; },
  },
  {
    name: 'leave_placeholder',
    why: 'generation scaffolding shipped to a human',
    expect: 'BLOCK',
    apply: (c) => { c.body += ' TODO: add the lifestyle section before sending.'; return c; },
  },
  {
    name: 'flip_risk_label',
    why: 'label contradicts the numeric score',
    expect: 'BLOCK',
    packs: ['medical'],
    apply: (c) => { c.riskLevel = (c.score !== null && c.score !== undefined && c.score > 0.5) ? 'low' : 'critical'; return c; },
  },
  {
    name: 'drop_evidence',
    why: 'the claims survive, the evidence does not',
    expect: 'BLOCK',
    apply: (c) => { c.evidence = []; return c; },
  },
  {
    name: 'truncate_body',
    why: 'the model stopped mid-thought',
    expect: 'NOT_PASS',
    apply: (c) => { c.body = c.body.slice(0, Math.max(30, Math.floor(c.body.length * 0.6))) + ' and the'; return c; },
  },
  {
    name: 'remove_timeframe',
    why: 'advice with no deadline is not followed',
    expect: 'NOT_PASS',
    apply: (c) => {
      const kill = /\b(?:within|in|after|every|next|by)\s+(?:the\s+)?(?:\d+|one|two|three|four|five|six|seven|ten|twelve|fourteen|twenty)\s*(?:business\s+)?(?:hour|day|week|month|year)s?\b|\b(?:immediately|same\s+day|today|now|urgently)\b/gi;
      c.body = c.body.replace(kill, 'soon');
      c.recommendations = (c.recommendations || []).map((r) => r.replace(kill, 'soon'));
      return c;
    },
  },
  {
    name: 'strip_recommendations',
    why: 'diagnosis without a next step',
    expect: 'NOT_PASS',
    apply: (c) => { c.recommendations = []; return c; },
  },
  {
    name: 'inject_pii',
    why: 'identifiers leaking into narrative prose',
    expect: 'NOT_PASS',
    apply: (c) => { c.body += ' Contact the patient on 9876543210 to arrange this.'; return c; },
  },
  {
    name: 'duplicate_sentence',
    why: 'padding to look thorough',
    expect: 'NOT_PASS',
    apply: (c) => {
      const s = String(c.body).split('. ')[1] || 'This is a screening signal and not a diagnosis';
      c.body += ' ' + s + '. ' + s + '.';
      return c;
    },
  },
  {
    name: 'unhedge_estimates',
    why: 'a heuristic estimate re-stated as a measurement',
    expect: 'NOT_PASS',
    // Only meaningful when some evidence is NOT validated. Stating a real
    // measurement plainly is correct behaviour, not a defect.
    requires: (fx) => (fx.content.evidence || []).some((e) =>
      ['partial', 'heuristic', 'fabricated_scale', 'unknown'].indexOf(e.fidelity) >= 0),
    apply: (c) => {
      c.body = c.body
        .replace(/was estimated at/gi, 'is')
        .replace(/estimated/gi, 'measured')
        .replace(/\baround\b/gi, 'exactly')
        .replace(/\babout\b/gi, 'exactly')
        .replace(/suggests/gi, 'proves');
      return c;
    },
  },
];

// ---------------------------------------------------------------------------
// NEGATIVE CONTROLS -- each must change NOTHING
// ---------------------------------------------------------------------------
const NOOPS = [
  {
    name: 'trailing_whitespace',
    why: 'normalization must absorb invisible edits',
    apply: (c) => { c.body = '   ' + c.body + '   \t\n\n'; c.title = c.title + '  '; return c; },
  },
  {
    name: 'crlf_line_endings',
    why: 'a Windows checkout must not mint a new certificate',
    apply: (c) => { c.body = c.body.replace(/\n/g, '\r\n') + '\r\n'; return c; },
  },
  {
    name: 'reordered_keys',
    why: 'JSON key order is not content',
    apply: (c) => {
      const out = {};
      for (const k of Object.keys(c).sort().reverse()) out[k] = c[k];
      return out;
    },
  },
  {
    name: 'reordered_evidence',
    why: 'the order tools happened to run in is not content',
    apply: (c) => { c.evidence = (c.evidence || []).slice().reverse(); return c; },
  },
];

function fixtures() {
  return fs.readdirSync(CORPUS_DIR)
    .filter((f) => f.endsWith('.json') && !f.startsWith('CERTIFICATES') && !f.startsWith('PARITY'))
    .sort()
    .map((f) => JSON.parse(fs.readFileSync(path.join(CORPUS_DIR, f), 'utf8')));
}

const all = fixtures();
const passing = all.filter((f) => (f.expect || {}).status === 'PASS');

console.log('\nAEGIS QUALITY GATE -- ADVERSARIAL MUTATION HARNESS');
console.log(`engine ${qg.ENGINE_VERSION}   base fixtures ${passing.length} (PASS only)   ` +
  `injections ${MUTATIONS.length}   negative controls ${NOOPS.length}\n`);

let caught = 0, missed = 0;
const misses = [];
const perMutation = {};

let skipped = 0;
for (const f of passing) {
  const pack = qg.pack(f.pack || 'medical');
  const baseDigest = qg.evaluate({ content: f.content, pack, profile: f.profile }).contentDigest;
  for (const m of MUTATIONS) {
    perMutation[m.name] = perMutation[m.name] || { caught: 0, total: 0, skipped: 0 };

    // A mutation that does not apply is reported as n/a, never silently folded
    // into the catch rate. Inflating a catch rate by counting inapplicable
    // cases as caught is the easiest way to make a weak gate look strong.
    if (Array.isArray(m.packs) && m.packs.indexOf(pack.packId) < 0) { perMutation[m.name].skipped++; skipped++; continue; }
    if (typeof m.requires === 'function' && !m.requires(f)) { perMutation[m.name].skipped++; skipped++; continue; }

    const mutated = m.apply(clone(f.content), f, pack);
    const v = qg.evaluate({ content: mutated, pack, profile: f.profile });
    if (v.contentDigest === baseDigest) { perMutation[m.name].skipped++; skipped++; continue; }

    // Some profiles/packs intentionally treat a defect as a flag rather than a
    // hard block. That is a policy decision, so the harness respects it instead
    // of demanding uniform severity everywhere.
    const soft = (Array.isArray(m.softProfiles) && m.softProfiles.indexOf(f.profile) >= 0) ||
                 (Array.isArray(m.softPacks) && m.softPacks.indexOf(pack.packId) >= 0);
    const wanted = soft && m.expect === 'BLOCK' ? 'NOT_PASS' : m.expect;
    const ok = wanted === 'BLOCK' ? v.status === 'BLOCK' : v.status !== 'PASS';

    perMutation[m.name].total++;
    if (ok) { caught++; perMutation[m.name].caught++; }
    else {
      missed++;
      misses.push({ fixture: f.id, mutation: m.name, why: m.why, got: v.status, wanted, score: v.score });
    }
    if (VERBOSE) {
      console.log(`  ${ok ? 'caught ' : 'MISSED '} ${f.id} / ${m.name} -> ${v.status} ${v.scorePercent}% ` +
        `[${v.blocking.join(',')}]`);
    }
  }
}

let noopOk = 0, noopBad = 0;
const noopFails = [];
for (const f of passing) {
  const pack = qg.pack(f.pack || 'medical');
  const base = qg.evaluate({ content: f.content, pack, profile: f.profile });
  for (const n of NOOPS) {
    const v = qg.evaluate({ content: n.apply(clone(f.content)), pack, profile: f.profile });
    if (v.certificateId === base.certificateId && v.verdictDigest === base.verdictDigest) noopOk++;
    else { noopBad++; noopFails.push({ fixture: f.id, noop: n.name, base: base.certificateId, got: v.certificateId }); }
  }
}

const W = (s, n) => String(s).padEnd(n).slice(0, n);
console.log(W('INJECTED DEFECT', 26) + W('CAUGHT', 10) + W('RATE', 8) + 'N/A');
console.log('-'.repeat(58));
for (const k of Object.keys(perMutation).sort()) {
  const r = perMutation[k];
  const rate = r.total ? Math.round((r.caught / r.total) * 100) + '%' : '-';
  console.log(W(k, 26) + W(`${r.caught}/${r.total}`, 10) + W(rate, 8) + (r.skipped || 0));
}
console.log('-'.repeat(58));
const total = caught + missed;
console.log(`catch rate            : ${caught}/${total} (${((caught / total) * 100).toFixed(1)}%)`);
console.log(`not applicable        : ${skipped} (pack/profile mismatch or mutation was a no-op)`);
console.log(`negative controls     : ${noopOk}/${noopOk + noopBad} certificates unchanged`);

if (misses.length) {
  console.log('\nMISSED DEFECTS (each one is a real hole in the policy pack):');
  for (const m of misses) {
    console.log(`  - ${m.fixture} / ${m.mutation}: wanted ${m.wanted}, got ${m.got} (${m.score}) -- ${m.why}`);
  }
}
if (noopFails.length) {
  console.log('\nNEGATIVE CONTROL FAILURES (formatting noise changed the certificate):');
  for (const n of noopFails) console.log(`  - ${n.fixture} / ${n.noop}: ${n.base} -> ${n.got}`);
}

const ok = missed === 0 && noopBad === 0;
console.log(ok
  ? '\nRESULT: every injected defect was caught, and no semantically empty edit moved a certificate.\n'
  : `\nRESULT: FAILED -- ${missed} missed defect(s), ${noopBad} unstable certificate(s).\n`);
process.exit(ok ? 0 : 1);
