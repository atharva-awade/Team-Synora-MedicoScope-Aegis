'use strict';
/**
 * FACT-PRESERVING REWRITE CONTRACT.
 *
 * The gate does not just say no; it hands the failure to an agent and asks for
 * a better draft. That is where most "AI fixes its own output" demos quietly
 * become dangerous, because the model does not only improve the prose -- it
 * rounds a number, drops a negation, softens a risk level. The document gets
 * more readable and less true, and every readability metric applauds.
 *
 * So a rewrite is treated as a proposal under contract. Before the rewritten
 * draft is even allowed back through the gate, this module proves that the
 * things a rewrite is NOT permitted to touch are byte-identical:
 *
 *   - the multiset of patient-facing numeric claims (value + unit)
 *   - the declared risk level and numeric risk score
 *   - the set of evidence envelopes cited
 *   - the negation polarity attached to each clinical term
 *
 * Prose is free. Facts are frozen. If the model changes a fact, the rewrite is
 * rejected before it can be scored -- so the gate can block its own fix, which
 * is exactly the behaviour that makes the loop safe to run unattended.
 */

const engine = require('./engine');
const claimsLib = require('./claims');
const text = require('./text');
const { digest } = require('./canonical');

const NEGATIONS = ['no ', 'not ', 'never ', 'without ', 'absent', 'denies', 'negative for', 'ruled out', 'free of', "n't "];

function claimKeyMultiset(content, pack) {
  const norm = engine.normalizeContent(content);
  const ctx = engine.buildContext(norm, pack);
  const counts = {};
  for (const c of claimsLib.patientClaims(ctx.boundClaims)) {
    const k = c.value + '|' + (c.unit || '-') + '|' + (c.role || '-');
    counts[k] = (counts[k] || 0) + 1;
  }
  return counts;
}

/** For each clinical term present, record whether a negation precedes it. */
function polarityMap(content, pack) {
  const norm = engine.normalizeContent(content);
  const hay = [norm.title, norm.body, norm.recommendations.join('\n')].join('\n').toLowerCase();
  const terms = Object.keys((pack.lexicons && pack.lexicons.jargon) || {}).sort();
  const out = {};
  for (const t of terms) {
    const at = hay.indexOf(t);
    if (at < 0) continue;
    const before = hay.slice(Math.max(0, at - 40), at);
    out[t] = NEGATIONS.some((n) => before.indexOf(n) >= 0) ? 'negated' : 'asserted';
  }
  return out;
}

function evidenceIds(content) {
  const norm = engine.normalizeContent(content);
  return norm.evidence.map((e) => e.toolId).sort();
}

function diffCounts(a, b) {
  const keys = Object.keys(Object.assign({}, a, b)).sort();
  const out = [];
  for (const k of keys) {
    const x = a[k] || 0, y = b[k] || 0;
    if (x !== y) out.push({ claim: k, before: x, after: y });
  }
  return out;
}

/**
 * @returns {{ok:boolean, violations:Array, beforeDigest:string, afterDigest:string}}
 */
function checkRewrite(before, after, pack) {
  const violations = [];

  const cBefore = claimKeyMultiset(before, pack);
  const cAfter = claimKeyMultiset(after, pack);
  const claimDrift = diffCounts(cBefore, cAfter);
  if (claimDrift.length) {
    violations.push({ type: 'NUMERIC_CLAIM_DRIFT', detail: 'rewrite altered patient-facing measurements', changes: claimDrift });
  }

  const nb = engine.normalizeContent(before);
  const na = engine.normalizeContent(after);
  if (nb.riskLevel !== na.riskLevel) {
    violations.push({ type: 'RISK_LEVEL_DRIFT', detail: `risk level changed ${nb.riskLevel} -> ${na.riskLevel}` });
  }
  if (nb.score !== na.score) {
    violations.push({ type: 'RISK_SCORE_DRIFT', detail: `risk score changed ${nb.score} -> ${na.score}` });
  }

  const eb = evidenceIds(before), ea = evidenceIds(after);
  if (digest(eb) !== digest(ea)) {
    violations.push({ type: 'EVIDENCE_SET_DRIFT', detail: 'cited evidence set changed', before: eb, after: ea });
  }

  const pb = polarityMap(before, pack), pa = polarityMap(after, pack);
  const flipped = [];
  for (const k of Object.keys(pb).sort()) {
    if (pa[k] && pa[k] !== pb[k]) flipped.push({ term: k, before: pb[k], after: pa[k] });
  }
  if (flipped.length) {
    violations.push({ type: 'NEGATION_POLARITY_FLIP', detail: 'a clinical statement changed meaning', changes: flipped });
  }

  violations.sort((a, b) => (a.type < b.type ? -1 : 1));
  return {
    ok: violations.length === 0,
    violations,
    beforeDigest: engine.contentDigestOf(nb),
    afterDigest: engine.contentDigestOf(na),
  };
}

/**
 * Run one guarded remediation step.
 * @returns {{accepted:boolean, contract, before, after, delta}}
 */
function applyGuardedRewrite(o) {
  const pack = o.pack;
  const profile = o.profile;
  const contract = checkRewrite(o.before, o.after, pack);
  const vBefore = engine.evaluate({ content: o.before, pack, profile });
  if (!contract.ok) {
    return { accepted: false, contract, before: vBefore, after: null, delta: null };
  }
  const vAfter = engine.evaluate({ content: o.after, pack, profile });
  return {
    accepted: true,
    contract,
    before: vBefore,
    after: vAfter,
    delta: diffVerdicts(vBefore, vAfter),
  };
}

/**
 * Explain a score change check-by-check, and say WHY it moved. When the pack
 * digest differs between the two verdicts, a score change may be rule drift
 * rather than a content improvement -- so the attribution is reported rather
 * than assumed. That is the difference between an audit trail and a scoreboard.
 */
function diffVerdicts(a, b) {
  const byId = (v) => {
    const m = {};
    for (const c of v.checks) m[c.id] = c;
    return m;
  };
  const A = byId(a), B = byId(b);
  const ids = Object.keys(Object.assign({}, A, B)).sort();
  const flips = [];
  for (const id of ids) {
    const x = A[id], y = B[id];
    if (!x || !y) { flips.push({ id, from: x ? (x.ok ? 'pass' : 'fail') : 'absent', to: y ? (y.ok ? 'pass' : 'fail') : 'absent' }); continue; }
    if (x.ok !== y.ok) flips.push({ id, from: x.ok ? 'pass' : 'fail', to: y.ok ? 'pass' : 'fail', severity: y.severity, detail: y.detail });
  }
  const dimDelta = a.dimensions.map((d, i) => ({
    id: d.id, before: d.score, after: b.dimensions[i] ? b.dimensions[i].score : null,
    delta: b.dimensions[i] ? Math.round((b.dimensions[i].score - d.score) * 10000) / 10000 : null,
  }));
  return {
    scoreBefore: a.score,
    scoreAfter: b.score,
    scoreDelta: Math.round((b.score - a.score) * 10000) / 10000,
    statusBefore: a.status,
    statusAfter: b.status,
    flips,
    dimensions: dimDelta,
    attribution: a.packDigest === b.packDigest ? 'content_only' : 'content_and_rules',
    packChanged: a.packDigest !== b.packDigest,
  };
}

/**
 * Isolate rule drift from content change. Re-runs the OLD pack on the NEW
 * content, so "the score went up" can be attributed honestly instead of being
 * quietly inflated by a policy edit.
 */
function attributeChange(o) {
  const oldOnOld = engine.evaluate({ content: o.beforeContent, pack: o.oldPack, profile: o.profile });
  const oldOnNew = engine.evaluate({ content: o.afterContent, pack: o.oldPack, profile: o.profile });
  const newOnNew = engine.evaluate({ content: o.afterContent, pack: o.newPack, profile: o.profile });
  const contentEffect = Math.round((oldOnNew.score - oldOnOld.score) * 10000) / 10000;
  const ruleEffect = Math.round((newOnNew.score - oldOnNew.score) * 10000) / 10000;
  return {
    scoreBefore: oldOnOld.score,
    scoreAfter: newOnNew.score,
    contentEffect,
    ruleEffect,
    dominant: Math.abs(contentEffect) >= Math.abs(ruleEffect) ? 'content' : 'rules',
    oldPack: { id: o.oldPack.packId, version: o.oldPack.packVersion, digest: o.oldPack.packDigest },
    newPack: { id: o.newPack.packId, version: o.newPack.packVersion, digest: o.newPack.packDigest },
  };
}

module.exports = { checkRewrite, applyGuardedRewrite, diffVerdicts, attributeChange, NEGATIONS };
