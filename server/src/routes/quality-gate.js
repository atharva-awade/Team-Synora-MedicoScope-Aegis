const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');

const qg = require('../../quality');
const ledger = require('../../aegis/ledger');
const QualityCertificate = require('../models/QualityCertificate');

/**
 * AEGIS QUALITY GATE -- HTTP surface.
 *
 * The design rule for this file: THE SERVER NEVER TRUSTS A SCORE IT DID NOT
 * COMPUTE. Every route that has consequences re-evaluates the submitted content
 * with its own engine and its own pack. The client-side Dart engine exists to
 * give a clinician instant feedback while typing; it has no authority, and it
 * cannot be used to talk the server into finalizing a blocked report.
 *
 * Routes:
 *   GET  /packs                      policy catalogue + predicate registry
 *   POST /evaluate                   pure verdict, nothing persisted
 *   POST /certify                    verdict + persisted certificate + ledger row
 *   POST /finalize                   the ONLY sanctioned path to sign content
 *   POST /verify                     re-derive a certificate from content
 *   GET  /verify/:certificateId      public seal check (no clinical content)
 *   GET  /certificate/:certificateId full certificate (authenticated)
 *   POST /rewrite/check              fact-preserving rewrite contract
 *   POST /critique/compile           validate agent-proposed assertions
 */

const ATTEST_SECRET = () => process.env.SERVICE_KEY || process.env.JWT_SECRET || '';
const VERIFY_BASE = () => (process.env.PUBLIC_BASE_URL || '').replace(/\/$/, '') + '/api/quality-gate/verify';

function resolvePack(body) {
  const id = (body && body.pack) || 'medical';
  return qg.pack(id);
}

function isClinician(user) {
  return user && (user.role === 'doctor' || user.role === 'admin');
}

// ── policy catalogue ────────────────────────────────────────────────────────
// Publishing the whole rule set is deliberate. A gate whose rules are secret
// cannot be argued with, and a rule nobody can read is a rule nobody can trust.
router.get('/packs', auth, (req, res) => {
  try {
    res.json({
      engineVersion: qg.ENGINE_VERSION,
      packs: qg.packIds().map((id) => qg.describePack(id)),
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ── pure evaluation (no side effects, safe to call on every keystroke) ──────
router.post('/evaluate', auth, (req, res) => {
  try {
    const body = req.body || {};
    if (!body.content) return res.status(400).json({ message: 'content is required' });
    const pack = resolvePack(body);
    const verdict = qg.evaluate({ content: body.content, pack, profile: body.profile });

    // Optional advisory layer: an agent may propose assertions, which are
    // compiled, executed, and reported -- but they can never move the verdict.
    let advisory = null;
    if (Array.isArray(body.proposals) && body.proposals.length) {
      const compiled = qg.critic.compile(body.proposals, pack);
      const ctx = qg.buildContext(qg.normalizeContent(body.content), pack);
      advisory = {
        findings: qg.critic.runAdvisory(compiled.accepted, ctx),
        rejected: compiled.rejected,
        authority: 'informational_only',
      };
    }

    res.json({ verdict, advisory, summary: qg.summarize(verdict) });
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// ── certify: evaluate + persist. Idempotent on (content, pack, profile). ───
router.post('/certify', auth, async (req, res) => {
  try {
    const body = req.body || {};
    if (!body.content) return res.status(400).json({ message: 'content is required' });
    const pack = resolvePack(body);
    const verdict = qg.evaluate({ content: body.content, pack, profile: body.profile });

    let advisory = [];
    if (Array.isArray(body.proposals) && body.proposals.length) {
      const compiled = qg.critic.compile(body.proposals, pack);
      const ctx = qg.buildContext(qg.normalizeContent(body.content), pack);
      advisory = qg.critic.runAdvisory(compiled.accepted, ctx);
    }

    // Same content + same pack + same profile is the same certificate, so a
    // repeat call returns the existing row rather than minting a duplicate.
    const existing = await QualityCertificate.findOne({ certificateId: verdict.certificateId }).lean();
    if (existing) {
      return res.json({ certificate: existing, verdict, reused: true });
    }

    const issuedAt = new Date();
    const cert = qg.certificate.issue({
      verdict,
      evaluatedAt: issuedAt.toISOString(),
      issuer: 'medicoscope-api',
      subjectRef: { recordId: body.recordId || '', patientRef: body.patientId || '' },
      advisory,
      secret: ATTEST_SECRET(),
      verifyBaseUrl: VERIFY_BASE(),
    });

    const doc = await QualityCertificate.create({
      certificateId: cert.certificateId,
      verdictDigest: cert.verdictDigest,
      contentDigest: cert.contentDigest,
      engineVersion: cert.engineVersion,
      packId: cert.packId,
      packVersion: cert.packVersion,
      packDigest: cert.packDigest,
      profile: cert.profile,
      status: cert.status,
      score: cert.score,
      dimensions: cert.dimensions,
      checks: verdict.checks,
      blocking: cert.blocking,
      mustFix: cert.mustFix,
      metrics: cert.metrics,
      claims: cert.claims,
      advisory,
      patientId: body.patientId || '',
      recordId: body.recordId || '',
      episodeId: body.episodeId || null,
      issuedAt,
      issuer: cert.issuer,
      issuedBy: req.user._id,
      attestation: cert.attestation,
      attestationAlg: cert.attestationAlg,
    });

    // The verdict joins the same hash-chained ledger the Aegis gate writes to,
    // so a quality decision sits in the same tamper-evident timeline as the
    // clinical decisions it governs.
    let auditSeq = null;
    if (body.patientId) {
      try {
        const row = await ledger.append({
          episodeId: body.episodeId || null,
          patientId: body.patientId,
          decisionType: 'quality_gate',
          riskLevel: (body.content.riskLevel || '').toLowerCase() || null,
          rationale: `quality_gate ${verdict.status} ${verdict.scorePercent}% cert=${verdict.certificateId} ` +
            `pack=${verdict.packId}@${verdict.packVersion} blocking=[${verdict.blocking.join(',')}]`,
          inputDigest: verdict.contentDigest,
          decidedBy: 'rule_engine',
          autonomous: true,
          rulesVersion: `${verdict.packId}@${verdict.packVersion}#${verdict.packDigest.slice(0, 12)}`,
        });
        auditSeq = row && row.seq != null ? row.seq : null;
        if (auditSeq != null) await QualityCertificate.updateOne({ _id: doc._id }, { $set: { auditSeq } });
      } catch (e) {
        // A ledger failure must be visible, not swallowed: the certificate is
        // still valid (it is reproducible from content), but its place in the
        // chain is missing and somebody has to know.
        console.error('quality-gate: ledger append failed for', verdict.certificateId, e && e.message);
      }
    }

    res.json({ certificate: Object.assign({}, doc.toObject(), { verifyUrl: cert.verifyUrl, sealLine: cert.sealLine }), verdict, reused: false });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ── finalize: the only sanctioned way to sign content ──────────────────────
router.post('/finalize', auth, async (req, res) => {
  try {
    const body = req.body || {};
    if (!body.content) return res.status(400).json({ message: 'content is required' });

    const pack = resolvePack(body);
    // Re-evaluate rather than trusting body.status / body.score. This is the
    // whole reason the route exists.
    const verdict = qg.evaluate({ content: body.content, pack, profile: body.profile });
    const override = body.override || null;

    if (verdict.status === 'BLOCK') {
      if (!override || !String(override.reason || '').trim()) {
        return res.status(409).json({
          message: 'Quality Gate BLOCKED this content. Finalization refused.',
          verdict,
          remediation: verdict.mustFix,
          overridePath: 'A doctor or admin may finalize anyway by supplying override.reason; ' +
            'the override is recorded in the append-only ledger and printed on the certificate.',
        });
      }
      if (!isClinician(req.user)) {
        return res.status(403).json({
          message: 'Only a clinician may override a BLOCKED quality verdict.',
          verdict,
        });
      }
    }

    const issuedAt = new Date();
    const cert = qg.certificate.issue({
      verdict,
      evaluatedAt: issuedAt.toISOString(),
      issuer: `clinician:${req.user._id}`,
      subjectRef: { recordId: body.recordId || '', patientRef: body.patientId || '' },
      secret: ATTEST_SECRET(),
      verifyBaseUrl: VERIFY_BASE(),
    });

    const update = {
      certificateId: cert.certificateId,
      verdictDigest: cert.verdictDigest,
      contentDigest: cert.contentDigest,
      engineVersion: cert.engineVersion,
      packId: cert.packId, packVersion: cert.packVersion, packDigest: cert.packDigest,
      profile: cert.profile, status: cert.status, score: cert.score,
      dimensions: cert.dimensions, checks: verdict.checks, blocking: cert.blocking,
      mustFix: cert.mustFix, metrics: cert.metrics, claims: cert.claims,
      patientId: body.patientId || '', recordId: body.recordId || '',
      episodeId: body.episodeId || null,
      issuedAt, issuer: cert.issuer, issuedBy: req.user._id,
      attestation: cert.attestation, attestationAlg: cert.attestationAlg,
      finalized: true, finalizedAt: issuedAt, finalizedBy: req.user._id,
      overrideReason: override ? String(override.reason).slice(0, 1000) : '',
      overriddenBy: override ? req.user._id : null,
    };
    const doc = await QualityCertificate.findOneAndUpdate(
      { certificateId: cert.certificateId }, { $set: update },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );

    if (body.patientId) {
      try {
        const row = await ledger.append({
          episodeId: body.episodeId || null,
          patientId: body.patientId,
          decisionType: override ? 'quality_gate_override' : 'quality_gate_final',
          riskLevel: (body.content.riskLevel || '').toLowerCase() || null,
          rationale: override
            ? `FINALIZED OVER BLOCK by clinician: ${String(override.reason).slice(0, 400)} ` +
              `| cert=${verdict.certificateId} blocking=[${verdict.blocking.join(',')}]`
            : `finalized ${verdict.status} ${verdict.scorePercent}% cert=${verdict.certificateId}`,
          inputDigest: verdict.contentDigest,
          decidedBy: 'clinician',
          autonomous: false,
          clinicianId: req.user._id,
          rulesVersion: `${verdict.packId}@${verdict.packVersion}#${verdict.packDigest.slice(0, 12)}`,
        });
        if (row && row.seq != null) await QualityCertificate.updateOne({ _id: doc._id }, { $set: { auditSeq: row.seq } });
      } catch (e) {
        console.error('quality-gate: finalize ledger append failed', e && e.message);
      }
    }

    res.json({
      finalized: true,
      overridden: !!override,
      certificate: Object.assign({}, doc.toObject(), { verifyUrl: cert.verifyUrl, sealLine: cert.sealLine }),
      verdict,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ── verify by re-derivation (needs the original content) ───────────────────
router.post('/verify', auth, async (req, res) => {
  try {
    const body = req.body || {};
    if (!body.content || !body.certificateId) {
      return res.status(400).json({ message: 'certificateId and content are required' });
    }
    const stored = await QualityCertificate.findOne({ certificateId: body.certificateId }).lean();
    if (!stored) return res.status(404).json({ message: 'certificate not found' });

    const pack = qg.pack(stored.packId);
    const result = qg.certificate.verify({ certificate: stored, content: body.content, pack });
    const attested = qg.certificate.verifyAttestation(stored, ATTEST_SECRET());

    res.json({
      certificateId: stored.certificateId,
      reproduced: result.ok,
      reason: result.reason,
      expectedVerdictDigest: result.expected,
      recomputedVerdictDigest: result.actual,
      attestation: attested,
      packPinned: `${stored.packId}@${stored.packVersion}#${stored.packDigest.slice(0, 12)}`,
      currentPackDigest: pack.packDigest,
      packDrifted: pack.packDigest !== stored.packDigest,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ── public seal check: what a QR code on a printed report resolves to ──────
// Intentionally unauthenticated and intentionally free of clinical content: it
// answers "is this seal real and what did the gate say", nothing more.
router.get('/verify/:certificateId', async (req, res) => {
  try {
    const cert = await QualityCertificate.findOne({ certificateId: req.params.certificateId })
      .select('certificateId verdictDigest contentDigest engineVersion packId packVersion packDigest ' +
              'profile status score dimensions blocking metrics issuedAt finalized finalizedAt ' +
              'overrideReason auditSeq episodeId patientId')
      .lean();
    if (!cert) return res.status(404).json({ found: false, message: 'No such certificate' });

    let ledgerIntegrity = null;
    if (cert.patientId) {
      try {
        const chain = await ledger.chainFor(cert.episodeId || null, cert.patientId);
        ledgerIntegrity = ledger.verifyChain(chain);
      } catch (_) { ledgerIntegrity = null; }
    }

    let packDrifted = null;
    try { packDrifted = qg.pack(cert.packId).packDigest !== cert.packDigest; } catch (_) {}

    res.json({
      found: true,
      certificateId: cert.certificateId,
      status: cert.status,
      scorePercent: Math.round(cert.score * 100),
      dimensions: cert.dimensions,
      blockingChecks: cert.blocking,
      metrics: cert.metrics,
      judgedBy: {
        engineVersion: cert.engineVersion,
        pack: `${cert.packId}@${cert.packVersion}`,
        packDigest: cert.packDigest,
        packDrifted,
      },
      digests: { verdict: cert.verdictDigest, content: cert.contentDigest },
      issuedAt: cert.issuedAt,
      finalized: cert.finalized,
      finalizedAt: cert.finalizedAt,
      finalizedOverBlock: !!cert.overrideReason,
      overrideReason: cert.overrideReason || null,
      ledgerIntegrity,
      note: 'This endpoint discloses the quality verdict only. It contains no clinical content ' +
            'and no patient identifiers. The certificate id is a function of the content digest, ' +
            'the policy pack digest and the engine version, so it can be recomputed independently.',
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.get('/certificate/:certificateId', auth, async (req, res) => {
  try {
    const cert = await QualityCertificate.findOne({ certificateId: req.params.certificateId }).lean();
    if (!cert) return res.status(404).json({ message: 'certificate not found' });
    if (!isClinician(req.user) && cert.patientId && String(cert.patientId) !== String(req.user._id) &&
        String(cert.patientId) !== String(req.user.uniqueCode || '')) {
      return res.status(403).json({ message: 'Not authorized for this certificate' });
    }
    res.json({ certificate: cert });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ── fact-preserving rewrite contract ───────────────────────────────────────
// An agent proposes a cleaner draft; this decides whether it is allowed to be
// scored at all. Prose may change. Measurements, risk level, cited evidence and
// negation polarity may not.
router.post('/rewrite/check', auth, (req, res) => {
  try {
    const body = req.body || {};
    if (!body.before || !body.after) return res.status(400).json({ message: 'before and after are required' });
    const pack = resolvePack(body);
    const result = qg.rewrite.applyGuardedRewrite({
      before: body.before, after: body.after, pack, profile: body.profile,
    });
    res.json({
      accepted: result.accepted,
      contract: result.contract,
      before: result.before,
      after: result.after,
      delta: result.delta,
      message: result.accepted
        ? 'Rewrite preserves every frozen fact and was scored.'
        : 'Rewrite REJECTED before scoring: it altered a fact a rewrite is not permitted to touch.',
    });
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// ── compile agent-proposed assertions (the critic's only entry point) ──────
router.post('/critique/compile', auth, (req, res) => {
  try {
    const body = req.body || {};
    const pack = resolvePack(body);
    const compiled = qg.critic.compile(body.proposals || [], pack);
    let findings = [];
    if (body.content && compiled.accepted.length) {
      const ctx = qg.buildContext(qg.normalizeContent(body.content), pack);
      findings = qg.critic.runAdvisory(compiled.accepted, ctx);
    }
    res.json({
      accepted: compiled.accepted,
      rejected: compiled.rejected,
      findings,
      authority: 'informational_only',
      note: 'Advisory findings are recorded on the certificate but are excluded from the verdict ' +
            'digest and cannot change PASS/WARN/BLOCK. Promotion into the policy pack (with a ' +
            'version bump and a golden-corpus re-run) is the only route to authority.',
      predicateRegistry: qg.predicates.ids(),
    });
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

module.exports = router;
