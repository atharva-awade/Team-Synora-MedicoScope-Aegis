'use strict';
/**
 * AEGIS QUALITY GATE ENGINE v3 -- deterministic policy interpreter.
 *
 * ONE INVARIANT, and everything else follows from it:
 *
 *     verdict = f(contentDigest, packDigest, engineVersion)
 *
 * f is a pure function. No clock, no randomness, no network, no LLM, no
 * database, no locale. Feed it the same content and the same policy pack and it
 * returns the same certificate id in a thousand years on a different runtime.
 * That is what the word "repeatable" has to mean if a certificate is going to
 * be worth anything, and it is why the timestamp lives OUTSIDE the hash:
 * a hash that includes `now` cannot be re-derived, so it proves nothing.
 *
 * The rules themselves are DATA (server/quality/packs/*.json). Swap the pack
 * and the same engine certifies a different domain; the medical pack is one
 * pack among several, not the engine's identity.
 */
const { canonical, digest, sha256Hex, shortId, score4 } = require('./canonical');
const text = require('./text');
const claimsLib = require('./claims');
const predicates = require('./predicates');

const ENGINE_VERSION = '3.0.0';
const VERDICT_SCHEMA = 'qg.verdict.v3';

/** Cost of a failed check, by severity. `info` never moves the score. */
const SEV_COST = { critical: 1.0, major: 0.6, minor: 0.25, info: 0.0 };
const SEV_ORDER = { info: 0, minor: 1, major: 2, critical: 3 };

class PackError extends Error {}

// ---------------------------------------------------------------------------
// pack loading + validation
// ---------------------------------------------------------------------------

/**
 * Validate a pack and stamp it with its content address. A pack that names a
 * predicate the engine does not implement fails HERE, at load, not silently at
 * evaluation time -- a rule that quietly does nothing is worse than no rule.
 */
function loadPack(raw) {
  if (!raw || typeof raw !== 'object') throw new PackError('pack must be an object');
  for (const f of ['packId', 'packVersion', 'dimensions', 'checks', 'profiles']) {
    if (raw[f] === undefined) throw new PackError(`pack missing required field: ${f}`);
  }
  const pack = JSON.parse(JSON.stringify(raw));
  delete pack.packDigest; // never self-referential

  const dimIds = new Set(pack.dimensions.map((d) => d.id));
  const seen = new Set();
  for (const c of pack.checks) {
    if (!c.id) throw new PackError('every check needs an id');
    if (seen.has(c.id)) throw new PackError(`duplicate check id: ${c.id}`);
    seen.add(c.id);
    if (!predicates.has(c.predicate)) {
      throw new PackError(`check ${c.id} names unknown predicate "${c.predicate}". Known: ${predicates.ids().join(', ')}`);
    }
    if (!dimIds.has(c.dimension)) throw new PackError(`check ${c.id} references unknown dimension "${c.dimension}"`);
    if (!SEV_COST[c.severity]) throw new PackError(`check ${c.id} has invalid severity "${c.severity}"`);
  }
  for (const pid of Object.keys(pack.profiles)) {
    const prof = pack.profiles[pid];
    for (const cid of Object.keys((prof && prof.overrides) || {})) {
      if (!seen.has(cid)) throw new PackError(`profile ${pid} overrides unknown check "${cid}"`);
    }
  }

  pack.packDigest = digest(pack);
  return pack;
}

// ---------------------------------------------------------------------------
// content normalization
// ---------------------------------------------------------------------------

/**
 * Canonical content form. Normalization happens BEFORE hashing so that a
 * trailing space, a CRLF, or a reordered key can never produce a different
 * certificate for identical content -- and so it cannot be used to launder a
 * blocked report into a new hash either.
 */
function normalizeContent(input) {
  const c = input || {};
  const str = (v) => (v === null || v === undefined ? '' : text.normalizeText(String(v)));
  const arr = (v) => (Array.isArray(v) ? v.map((x) => str(x)).filter((x) => x.length > 0) : []);
  const numOrNull = (v) => {
    const n = Number(v);
    return v === null || v === undefined || !Number.isFinite(n) ? null : n;
  };

  const evidence = (Array.isArray(c.evidence) ? c.evidence : []).map((e, i) => ({
    toolId: str((e && (e.toolId || e.id)) || `evidence[${i}]`),
    modality: (e && e.modality) ? str(e.modality) : null,
    fidelity: (e && e.fidelity) ? str(e.fidelity) : 'unknown',
    label: (e && (e.label || e.finding)) ? str(e.label || e.finding) : null,
    value: numOrNull(e && e.value),
    unit: (e && e.unit) ? str(e.unit) : null,
    provenance: (e && e.provenance && typeof e.provenance === 'object') ? e.provenance : {},
    findings: (e && Array.isArray(e.findings) ? e.findings : []).map((f) => ({
      label: str(f && (f.label || f.name || f.key)),
      value: numOrNull(f && f.value),
      unit: (f && f.unit) ? str(f.unit) : null,
    })),
  }));
  // Evidence order must not change the certificate.
  evidence.sort((a, b) => (a.toolId < b.toolId ? -1 : a.toolId > b.toolId ? 1 : (a.label || '') < (b.label || '') ? -1 : 1));

  return {
    kind: str(c.kind || 'report'),
    subject: str(c.subject),
    title: str(c.title || c.finding),
    category: str(c.category),
    riskLevel: str(c.riskLevel).toLowerCase(),
    score: numOrNull(c.score),
    confidence: numOrNull(c.confidence),
    body: str(c.body || c.text || c.doctorNotes),
    recommendations: arr(c.recommendations),
    disclaimer: str(c.disclaimer),
    evidence,
    locale: str(c.locale || 'en'),
  };
}

function contentDigestOf(normalized) {
  return digest(normalized);
}

// ---------------------------------------------------------------------------
// evaluation context
// ---------------------------------------------------------------------------

function buildContext(content, pack) {
  const body = content.body;
  const recommendationsText = content.recommendations.join('\n').toLowerCase();
  const fullText = [content.title, body, content.recommendations.join('\n'), content.disclaimer]
    .filter((s) => s && s.length)
    .join('\n');

  const ce = pack.claimExtraction || {};
  const rawClaims = claimsLib.extractClaims(fullText, {
    bareNumberLabels: ce.bareNumberLabels || [],
    ignorePatterns: ce.ignorePatterns || [],
    thresholdCues: ce.thresholdCues || null,
    thresholdCueWindow: ce.thresholdCueWindow || 18,
  });
  const facts = claimsLib.evidenceFacts(content.evidence);
  const boundClaims = claimsLib.bindClaims(rawClaims, facts, {
    tolerances: ce.tolerances,
    allowCrossUnitValueMatch: !!ce.allowCrossUnitValueMatch,
  });

  return {
    content,
    pack,
    body,
    text: fullText,
    lowerText: fullText.toLowerCase(),
    recommendationsText,
    sentences: text.sentences(fullText),
    read: text.readability(fullText),
    facts,
    boundClaims,
    groundingCoverage: claimsLib.coverage(boundClaims),
  };
}

// ---------------------------------------------------------------------------
// the gate
// ---------------------------------------------------------------------------

function applicableChecks(pack, profileId) {
  const prof = pack.profiles[profileId];
  if (!prof) throw new PackError(`unknown profile "${profileId}" in pack ${pack.packId}`);
  const overrides = prof.overrides || {};
  const out = [];
  for (const c of pack.checks) {
    if (Array.isArray(c.profiles) && c.profiles.indexOf(profileId) < 0) continue;
    if (Array.isArray(prof.exclude) && prof.exclude.indexOf(c.id) >= 0) continue;
    const ov = overrides[c.id] || {};
    if (ov.disabled) continue;
    out.push({
      id: c.id,
      dimension: c.dimension,
      predicate: c.predicate,
      severity: ov.severity || c.severity,
      weight: ov.weight !== undefined ? ov.weight : (c.weight !== undefined ? c.weight : 1),
      message: c.message || c.id,
      remedy: ov.remedy || c.remedy || '',
      args: Object.assign({}, c.args || {}, ov.args || {}),
    });
  }
  // Stable execution order -> stable digest, regardless of pack file ordering.
  out.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return out;
}

/**
 * Run the gate.
 * @param {Object} o
 * @param {Object} o.content  raw content (normalized internally)
 * @param {Object} o.pack     a pack already through loadPack()
 * @param {string} o.profile  profile id inside the pack
 * @returns {Object} verdict  (no timestamps, no ids from outside)
 */
function evaluate(o) {
  const pack = o.pack;
  const profileId = o.profile || pack.defaultProfile || Object.keys(pack.profiles)[0];
  const prof = pack.profiles[profileId];
  if (!prof) throw new PackError(`unknown profile "${profileId}"`);

  const content = normalizeContent(o.content);
  const ctx = buildContext(content, pack);
  const checks = applicableChecks(pack, profileId);

  const results = [];
  for (const c of checks) {
    const fn = predicates.get(c.predicate);
    let r;
    try {
      r = fn(ctx, c.args);
    } catch (err) {
      // A predicate that throws is a BUG, and a buggy gate must fail closed --
      // never wave content through because the checker crashed.
      r = { ok: false, detail: `predicate error: ${err && err.message}`, data: { error: 'predicate_exception' } };
    }
    results.push({
      id: c.id,
      dimension: c.dimension,
      predicate: c.predicate,
      severity: c.severity,
      weight: c.weight,
      ok: !!r.ok,
      message: c.message,
      remedy: r.ok ? '' : c.remedy,
      detail: String(r.detail || ''),
      data: r.data || {},
    });
  }

  // --- dimension scoring -------------------------------------------------
  const dimWeights = prof.dimensionWeights || {};
  const dimensions = [];
  for (const d of pack.dimensions) {
    const own = results.filter((r) => r.dimension === d.id);
    let total = 0, failed = 0;
    for (const r of own) {
      const cost = r.weight * SEV_COST[r.severity];
      total += cost;
      if (!r.ok) failed += cost;
    }
    const dScore = total > 0 ? 1 - failed / total : 1;
    dimensions.push({
      id: d.id,
      title: d.title || d.id,
      weight: dimWeights[d.id] !== undefined ? dimWeights[d.id] : (d.weight !== undefined ? d.weight : 1),
      score: score4(dScore),
      checkCount: own.length,
      failedCount: own.filter((r) => !r.ok).length,
    });
  }
  dimensions.sort((a, b) => (a.id < b.id ? -1 : 1));

  let wSum = 0, wAcc = 0;
  for (const d of dimensions) { wSum += d.weight; wAcc += d.weight * d.score; }
  const score = score4(wSum > 0 ? wAcc / wSum : 1);

  // --- status ------------------------------------------------------------
  const th = prof.thresholds || {};
  const passAt = th.pass !== undefined ? th.pass : 0.85;
  const blockAt = th.block !== undefined ? th.block : 0.6;

  const failures = results.filter((r) => !r.ok);
  const blockingIds = failures.filter((r) => r.severity === 'critical').map((r) => r.id).sort();
  const majorIds = failures.filter((r) => r.severity === 'major').map((r) => r.id).sort();

  let status;
  if (blockingIds.length > 0 || score < blockAt) status = 'BLOCK';
  else if (majorIds.length > 0 || score < passAt) status = 'WARN';
  else status = 'PASS';

  // --- digest ------------------------------------------------------------
  // Only decision-bearing facts go in. `detail` and `message` are prose and are
  // deliberately excluded so that a copy-edit to a message string, or a
  // runtime's number-to-string formatting, can never fork the hash.
  const contentDigest = contentDigestOf(content);
  const digestBody = {
    schema: VERDICT_SCHEMA,
    engineVersion: ENGINE_VERSION,
    packId: pack.packId,
    packVersion: pack.packVersion,
    packDigest: pack.packDigest,
    profile: profileId,
    contentDigest,
    status,
    score,
    checks: results.map((r) => ({ id: r.id, ok: r.ok, severity: r.severity, data: r.data })),
  };
  const verdictDigest = digest(digestBody);

  return {
    schema: VERDICT_SCHEMA,
    engineVersion: ENGINE_VERSION,
    packId: pack.packId,
    packVersion: pack.packVersion,
    packDigest: pack.packDigest,
    profile: profileId,
    profileTitle: prof.title || profileId,
    contentDigest,
    status,
    score,
    scorePercent: Math.round(score * 100),
    thresholds: { pass: passAt, block: blockAt },
    dimensions,
    checks: results,
    blocking: blockingIds,
    majorFailures: majorIds,
    mustFix: failures
      .filter((r) => r.severity === 'critical' || r.severity === 'major')
      .sort((a, b) => SEV_ORDER[b.severity] - SEV_ORDER[a.severity] || (a.id < b.id ? -1 : 1))
      .map((r) => ({ id: r.id, severity: r.severity, message: r.message, detail: r.detail, remedy: r.remedy })),
    metrics: {
      fkGrade: ctx.read.fkGrade,
      readingEase: ctx.read.readingEase,
      gradeBand: text.gradeBand(ctx.read.fkGrade),
      wordCount: ctx.read.wordCount,
      sentenceCount: ctx.read.sentenceCount,
      longestSentenceWords: ctx.read.longestSentenceWords,
      claimCount: ctx.boundClaims.filter((c) => (c.kind || 'patient') === 'patient').length,
      boundClaimCount: ctx.boundClaims.filter((c) => (c.kind || 'patient') === 'patient' && c.boundTo).length,
      thresholdClaimCount: ctx.boundClaims.filter((c) => c.kind === 'threshold').length,
      groundingCoverage: score4(ctx.groundingCoverage),
      evidenceCount: content.evidence.length,
    },
    claims: ctx.boundClaims.map((c) => ({
      raw: c.raw, value: c.value, unit: c.unit, role: c.role, kind: c.kind || 'patient',
      boundTo: c.boundTo, matchKind: c.matchKind, fidelity: c.fidelity,
    })),
    verdictDigest,
    certificateId: shortId(verdictDigest),
  };
}

/** Deterministic single-line summary, handy for CI logs and demo overlays. */
function summarize(v) {
  return `${v.status} ${v.scorePercent}% cert=${v.certificateId} pack=${v.packId}@${v.packVersion} ` +
    `grade=${v.metrics.fkGrade} grounding=${Math.round(v.metrics.groundingCoverage * 100)}% ` +
    `blocking=[${v.blocking.join(',')}]`;
}

module.exports = {
  ENGINE_VERSION, VERDICT_SCHEMA, SEV_COST, PackError,
  loadPack, normalizeContent, contentDigestOf, buildContext, applicableChecks,
  evaluate, summarize,
};
