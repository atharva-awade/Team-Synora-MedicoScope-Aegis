const mongoose = require('mongoose');

/**
 * QualityCertificate - the persisted record of one Quality Gate verdict.
 *
 * Two identities live in this document and they are deliberately different:
 *
 *   certificateId / verdictDigest   REPRODUCIBLE. Derived purely from
 *                                   (contentDigest, packDigest, engineVersion).
 *                                   Anyone with the content and the pack can
 *                                   recompute them offline, with no access to
 *                                   this database and no trust in this server.
 *
 *   issuedAt / issuer / attestation NOT reproducible, and not meant to be.
 *                                   They record who signed and when, and they
 *                                   are excluded from the digest so that the id
 *                                   stays stable.
 *
 * `finalized` is the gate that actually matters: a report is only finalized
 * through the server route, which re-evaluates the content itself rather than
 * trusting a score the client sent. The old flow stored finalization in
 * SharedPreferences on the device, which means the audit trail could be edited
 * by the person being audited.
 */
const qualityCertificateSchema = new mongoose.Schema({
  // --- reproducible identity ---
  certificateId: { type: String, required: true, unique: true, index: true },
  verdictDigest: { type: String, required: true, index: true },
  contentDigest: { type: String, required: true, index: true },
  engineVersion: { type: String, required: true },
  packId: { type: String, required: true },
  packVersion: { type: String, required: true },
  packDigest: { type: String, required: true },
  profile: { type: String, required: true },

  // --- verdict ---
  status: { type: String, enum: ['PASS', 'WARN', 'BLOCK'], required: true, index: true },
  score: { type: Number, required: true },
  dimensions: { type: mongoose.Schema.Types.Mixed, default: [] },
  checks: { type: mongoose.Schema.Types.Mixed, default: [] },
  blocking: { type: [String], default: [] },
  mustFix: { type: mongoose.Schema.Types.Mixed, default: [] },
  metrics: { type: mongoose.Schema.Types.Mixed, default: {} },
  claims: { type: mongoose.Schema.Types.Mixed, default: [] },

  // --- advisory layer (agent-proposed, never authoritative) ---
  advisory: { type: mongoose.Schema.Types.Mixed, default: [] },

  // --- subject linkage (references, not clinical content) ---
  patientId: { type: String, default: '', index: true },
  recordId: { type: String, default: '' },
  episodeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Episode', default: null },

  // --- issuance ---
  issuedAt: { type: Date, required: true },
  issuer: { type: String, default: 'medicoscope-api' },
  issuedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  attestation: { type: String, default: null },
  attestationAlg: { type: String, default: null },

  // --- finalization (server-authoritative) ---
  finalized: { type: Boolean, default: false, index: true },
  finalizedAt: { type: Date, default: null },
  finalizedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },

  // A BLOCK can only be finalized by a named clinician giving a reason, and the
  // override is itself written to the hash-chained ledger.
  overrideReason: { type: String, default: '' },
  overriddenBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  auditSeq: { type: Number, default: null },
}, { timestamps: true });

// The same content judged by the same pack is the same certificate. This index
// makes that identity a database-level fact, not a convention.
qualityCertificateSchema.index({ contentDigest: 1, packDigest: 1, profile: 1 });
qualityCertificateSchema.index({ patientId: 1, createdAt: -1 });

module.exports = mongoose.model('QualityCertificate', qualityCertificateSchema);
