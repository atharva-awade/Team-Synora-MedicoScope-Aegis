'use strict';
/**
 * CERTIFICATE ENVELOPE.
 *
 * Two properties that are usually conflated, kept deliberately separate here:
 *
 *   IDENTITY is reproducible.   certificateId = f(content, pack, engine).
 *                               Anyone holding the content and the pack can
 *                               re-derive it offline, forever, with no server.
 *
 *   ISSUANCE is attributable.   The timestamp, the issuer, and an HMAC
 *                               attestation live OUTSIDE the digest. They say
 *                               who signed and when, and they can be revoked --
 *                               without ever changing the id.
 *
 * Most "audit hash" implementations fold `Date.now()` into the hash, which feels
 * more secure and is strictly worse: the hash can never be recomputed, so it
 * proves nothing to anybody. Splitting the two is what makes the seal on the
 * printed PDF independently checkable.
 */
const crypto = require('crypto');
const engine = require('./engine');
const { digest } = require('./canonical');

const CERT_SCHEMA = 'qg.certificate.v3';

function attest(verdictDigest, issuedAt, issuer, secret) {
  if (!secret) return null;
  return crypto.createHmac('sha256', String(secret))
    .update([verdictDigest, issuedAt, issuer || ''].join('|'), 'utf8')
    .digest('hex');
}

/**
 * @param {Object} o
 * @param {Object} o.verdict      from engine.evaluate()
 * @param {string} o.evaluatedAt  ISO string, supplied by the CALLER (the engine
 *                                has no clock, by design)
 * @param {string} [o.issuer]     e.g. "medicoscope-api" or a clinician id
 * @param {Object} [o.subjectRef] non-PII pointers: { recordId, episodeId, patientRef }
 * @param {Array}  [o.advisory]   agent-proposed findings (never in the digest)
 * @param {string} [o.secret]     HMAC key for the attestation
 * @param {string} [o.verifyBaseUrl]
 */
function issue(o) {
  const v = o.verdict;
  const issuedAt = o.evaluatedAt;
  const issuer = o.issuer || 'unattributed';
  const attestation = attest(v.verdictDigest, issuedAt, issuer, o.secret);

  return {
    schema: CERT_SCHEMA,

    // --- reproducible identity (all inside verdictDigest) ---
    certificateId: v.certificateId,
    verdictDigest: v.verdictDigest,
    contentDigest: v.contentDigest,
    packId: v.packId,
    packVersion: v.packVersion,
    packDigest: v.packDigest,
    engineVersion: v.engineVersion,
    profile: v.profile,
    status: v.status,
    score: v.score,
    scorePercent: v.scorePercent,

    // --- human-facing summary ---
    dimensions: v.dimensions,
    metrics: v.metrics,
    blocking: v.blocking,
    mustFix: v.mustFix,
    claims: v.claims,

    // --- issuance metadata (deliberately OUTSIDE the digest) ---
    issuedAt,
    issuer,
    subjectRef: o.subjectRef || {},
    attestation,
    attestationAlg: attestation ? 'HMAC-SHA256' : null,

    // --- advisory layer: recorded, never authoritative ---
    advisory: o.advisory || [],
    advisoryAuthority: 'informational_only',

    verifyUrl: o.verifyBaseUrl ? String(o.verifyBaseUrl).replace(/\/$/, '') + '/' + v.certificateId : null,
    sealLine: sealLine(v),
  };
}

/** One line safe to print on a report footer or read aloud on stage. */
function sealLine(v) {
  return [
    'AEGIS QUALITY GATE',
    v.status,
    v.scorePercent + '%',
    'cert ' + v.certificateId,
    'pack ' + v.packId + '@' + v.packVersion,
    'engine ' + v.engineVersion,
  ].join('  |  ');
}

/**
 * Independently re-derive the verdict from content + pack and compare.
 * This is the whole point: a third party can check the seal with no access to
 * our database and no trust in our server.
 * @returns {{ok:boolean, reason:string, expected:string, actual:string, verdict:Object}}
 */
function verify(o) {
  const cert = o.certificate;
  const pack = o.pack;
  if (cert.packDigest && pack.packDigest && cert.packDigest !== pack.packDigest) {
    return {
      ok: false, reason: 'pack_mismatch',
      expected: cert.packDigest, actual: pack.packDigest, verdict: null,
    };
  }
  const v = engine.evaluate({ content: o.content, pack, profile: cert.profile });
  if (v.contentDigest !== cert.contentDigest) {
    return { ok: false, reason: 'content_tampered', expected: cert.contentDigest, actual: v.contentDigest, verdict: v };
  }
  if (v.verdictDigest !== cert.verdictDigest) {
    return { ok: false, reason: 'verdict_mismatch', expected: cert.verdictDigest, actual: v.verdictDigest, verdict: v };
  }
  return { ok: true, reason: 'reproduced', expected: cert.verdictDigest, actual: v.verdictDigest, verdict: v };
}

/** Verify the issuance attestation (needs the server secret). */
function verifyAttestation(cert, secret) {
  if (!cert.attestation) return { ok: false, reason: 'no_attestation' };
  const expected = attest(cert.verdictDigest, cert.issuedAt, cert.issuer, secret);
  const a = Buffer.from(String(cert.attestation));
  const b = Buffer.from(String(expected));
  const ok = a.length === b.length && crypto.timingSafeEqual(a, b);
  return { ok, reason: ok ? 'attested' : 'attestation_mismatch' };
}

module.exports = { CERT_SCHEMA, issue, verify, verifyAttestation, sealLine, attest };
