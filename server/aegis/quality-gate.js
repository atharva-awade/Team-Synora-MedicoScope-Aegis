'use strict';
/**
 * DEPRECATED SHIM -- kept only so nothing that imported this path breaks.
 *
 * The original version of this file was a 119-line hand-rolled scorer that
 * shipped with three defects worth naming, because they are the exact traps this
 * rewrite exists to avoid:
 *
 *   1. It was never imported by any route. It was dead code, so no verdict it
 *      produced ever reached a user.
 *   2. Its audit hash folded `Date.now()` into the hashed input, so the same
 *      content produced a different hash every call. A hash that cannot be
 *      recomputed proves nothing -- which makes "repeatable" false at the
 *      cryptographic level, not just the semantic one.
 *   3. Its rules diverged from the client-side Dart copy (QG-SERVER-2026.2 vs
 *      QG-CLINICAL-2026.2), so phone and server disagreed about the same report.
 *
 * The real engine now lives in server/quality/ -- one rules-as-data pack, one
 * pure evaluator, a golden corpus, and a Dart port held to byte-parity by a
 * generated vector file.
 *
 * Prefer:  const qg = require('../quality');
 */
const qg = require('../quality');

const RULES_VERSION = 'QG-SERVER-2026.2-DEPRECATED';

/**
 * Legacy adapter. Maps the old loose `content` shape onto the v3 engine and
 * returns the old response shape, so old callers keep working while new code
 * uses the engine directly.
 *
 * @deprecated use require('../quality').evaluate({ content, pack, profile })
 */
function evaluateQualityGate(content = {}) {
  const pack = qg.pack('medical');
  const profile = content.profile || 'clinician_report';
  const v = qg.evaluate({
    content: {
      title: content.title || content.finding || content.category || '',
      category: content.category || '',
      riskLevel: content.riskLevel || 'low',
      score: content.score,
      confidence: content.confidence,
      body: content.text || content.doctorNotes || '',
      recommendations: content.recommendations || [],
      disclaimer: content.disclaimer || '',
      evidence: content.evidence || [],
    },
    pack,
    profile,
  });

  return {
    overallScore: v.scorePercent,
    status: v.status === 'PASS' ? 'PASSED' : v.status === 'WARN' ? 'WARNING' : 'BLOCKED',
    passed: v.status !== 'BLOCK',
    dimensions: v.dimensions.map((d) => ({
      type: d.id,
      title: d.title,
      score: d.score,
      passedChecks: v.checks.filter((c) => c.dimension === d.id && c.ok).map((c) => c.message),
      warnings: v.checks.filter((c) => c.dimension === d.id && !c.ok && c.severity !== 'critical').map((c) => c.detail),
      criticalIssues: v.checks.filter((c) => c.dimension === d.id && !c.ok && c.severity === 'critical').map((c) => c.detail),
    })),
    // NOTE: unlike the old implementation this is stable for identical content.
    auditHash: v.certificateId.replace('-', ''),
    certificateId: v.certificateId,
    verdictDigest: v.verdictDigest,
    rulesVersion: `${v.packId}@${v.packVersion}`,
    engineVersion: v.engineVersion,
    evaluatedAt: new Date().toISOString(),
    verdict: v,
  };
}

module.exports = { evaluateQualityGate, RULES_VERSION, engine: qg };
