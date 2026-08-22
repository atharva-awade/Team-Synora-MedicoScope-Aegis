'use strict';
/**
 * THE CRITIC COMPILER -- how an LLM is allowed to participate in a gate that
 * must stay deterministic.
 *
 * The tension is real and most teams paper over it: judges want agentic AI in
 * the loop, but an LLM is non-deterministic, so anything an LLM decides cannot
 * be part of a repeatable verdict. Putting a model inside the gate destroys the
 * one property the gate exists to provide.
 *
 * Resolution: THE AGENT NEVER SCORES. It writes tests.
 *
 *   1. A critic agent reads the content and proposes ASSERTIONS -- structured
 *      references to predicates the engine already implements, with arguments.
 *      It cannot propose behaviour, only configuration. There is no eval here.
 *   2. `compile()` validates every proposal against the registry and an
 *      argument allowlist, and rejects the rest with a reason.
 *   3. Accepted assertions run and produce ADVISORY findings. Advisory findings
 *      are recorded in the certificate but are excluded from the verdict digest
 *      and cannot move PASS/WARN/BLOCK. The certificate stays reproducible even
 *      though a stochastic model touched the workflow.
 *   4. The only route to authority is `promote()`: an advisory assertion becomes
 *      a real check by being written into the pack with a version bump -- which
 *      forces the golden corpus to be re-verified before it can ship.
 *
 * So the gate can LEARN, and it is still a pure function of
 * (content, pack, engine). Non-determinism is quarantined, not invited in.
 */

const predicates = require('./predicates');
const { digest } = require('./canonical');

/** Predicates whose arguments may contain a caller-supplied regex. */
const REGEX_ARG_WHITELIST = { piiAbsent: ['patterns'], timeframePresent: ['pattern'] };
const MAX_PROPOSALS = 24;
const MAX_REGEX_LENGTH = 200;
const MAX_ARG_BYTES = 4096;
const ALLOWED_SEVERITIES = ['minor', 'major'];  // an advisory can never claim 'critical'

/** Cheap catastrophic-backtracking screen. Not a proof; a tripwire. */
function looksLikeReDoS(src) {
  if (src.length > MAX_REGEX_LENGTH) return true;
  if (/(\([^)]*[+*]\)[+*])|(\[[^\]]*\][+*]\s*[+*])|(\{\d+,\}\s*[+*])/.test(src)) return true;
  const nestedQuant = (src.match(/[+*]/g) || []).length;
  return nestedQuant > 8;
}

function argsAreData(v, depth) {
  const d = depth || 0;
  if (d > 4) return false;
  if (v === null) return true;
  const t = typeof v;
  if (t === 'string' || t === 'number' || t === 'boolean') return true;
  if (Array.isArray(v)) return v.every((x) => argsAreData(x, d + 1));
  if (t === 'object') {
    return Object.keys(v).every((k) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) && argsAreData(v[k], d + 1));
  }
  return false;   // functions, symbols, undefined -> not data
}

/**
 * Validate agent-proposed assertions.
 * @param {Array} proposals [{ predicate, args, dimension, severity, rationale }]
 * @param {Object} pack     loaded pack (for dimension validation)
 * @returns {{accepted: Array, rejected: Array}} deterministically ordered
 */
function compile(proposals, pack) {
  const accepted = [];
  const rejected = [];
  const list = Array.isArray(proposals) ? proposals.slice(0, MAX_PROPOSALS) : [];
  const dims = new Set((pack && pack.dimensions ? pack.dimensions : []).map((d) => d.id));

  for (const raw of list) {
    const p = raw || {};
    const reject = (reason) => rejected.push({
      predicate: p.predicate || null, reason,
      rationale: typeof p.rationale === 'string' ? p.rationale.slice(0, 400) : '',
    });

    if (!p.predicate || !predicates.has(p.predicate)) { reject('unknown_predicate'); continue; }
    const args = p.args === undefined ? {} : p.args;
    if (!argsAreData(args)) { reject('args_not_data'); continue; }
    if (JSON.stringify(args).length > MAX_ARG_BYTES) { reject('args_too_large'); continue; }

    // Regex arguments only where the predicate declares it, and only after a
    // ReDoS screen -- an LLM-authored regex is untrusted input by definition.
    const allowedRegexKeys = REGEX_ARG_WHITELIST[p.predicate] || [];
    let regexProblem = null;
    for (const k of Object.keys(args)) {
      const looksRegexy = /pattern/i.test(k);
      if (!looksRegexy) continue;
      if (allowedRegexKeys.indexOf(k) < 0) { regexProblem = 'regex_arg_not_permitted:' + k; break; }
      const vals = Array.isArray(args[k]) ? args[k] : [args[k]];
      for (const src of vals) {
        if (typeof src !== 'string') { regexProblem = 'regex_arg_not_string:' + k; break; }
        if (looksLikeReDoS(src)) { regexProblem = 'regex_arg_redos_risk:' + k; break; }
        try { new RegExp(src); } catch (e) { regexProblem = 'regex_arg_invalid:' + k; break; }
      }
      if (regexProblem) break;
    }
    if (regexProblem) { reject(regexProblem); continue; }

    const dimension = dims.has(p.dimension) ? p.dimension : 'structure';
    const severity = ALLOWED_SEVERITIES.indexOf(p.severity) >= 0 ? p.severity : 'minor';
    const body = { predicate: p.predicate, args, dimension, severity };
    accepted.push({
      id: 'ADV_' + digest(body).slice(0, 10).toUpperCase(),
      predicate: p.predicate,
      args,
      dimension,
      severity,
      rationale: typeof p.rationale === 'string' ? p.rationale.slice(0, 400) : '',
      origin: 'agent_proposed',
    });
  }

  // Deduplicate on the content-addressed id, then order deterministically so
  // two runs over the same proposal set produce an identical advisory block.
  const seen = new Set();
  const deduped = [];
  for (const a of accepted.sort((x, y) => (x.id < y.id ? -1 : x.id > y.id ? 1 : 0))) {
    if (seen.has(a.id)) continue;
    seen.add(a.id);
    deduped.push(a);
  }
  rejected.sort((a, b) => (String(a.predicate) + a.reason < String(b.predicate) + b.reason ? -1 : 1));
  return { accepted: deduped, rejected };
}

/**
 * Execute compiled assertions. Returns ADVISORY findings only.
 * These are excluded from the verdict digest by construction -- the caller adds
 * them to the certificate envelope, never to `evaluate()`'s digest body.
 */
function runAdvisory(assertions, ctx) {
  const findings = [];
  for (const a of assertions) {
    const fn = predicates.get(a.predicate);
    let r;
    try {
      r = fn(ctx, a.args);
    } catch (err) {
      r = { ok: false, detail: 'predicate error: ' + (err && err.message), data: { error: 'predicate_exception' } };
    }
    findings.push({
      id: a.id, predicate: a.predicate, dimension: a.dimension, severity: a.severity,
      ok: !!r.ok, detail: String(r.detail || ''), data: r.data || {},
      rationale: a.rationale, origin: a.origin,
      authority: 'advisory_only',
    });
  }
  findings.sort((a, b) => (a.id < b.id ? -1 : 1));
  return findings;
}

/**
 * Promote an advisory assertion into the pack as a first-class check.
 * Returns a NEW pack object (never mutates) with the minor version bumped and a
 * changelog entry. The caller MUST re-run the golden corpus before shipping it;
 * harness/promote.js refuses to write a pack whose promotion changes an existing
 * fixture's expected verdict without an explicit acknowledgement.
 */
function promote(pack, assertion, opts) {
  const o = opts || {};
  const next = JSON.parse(JSON.stringify(pack));
  delete next.packDigest;

  const id = o.id || assertion.id.replace(/^ADV_/, 'PRO_');
  if (next.checks.some((c) => c.id === id)) throw new Error('check id already exists: ' + id);

  next.checks.push({
    id,
    dimension: assertion.dimension,
    predicate: assertion.predicate,
    severity: o.severity || assertion.severity,
    weight: o.weight !== undefined ? o.weight : 1,
    args: assertion.args,
    message: o.message || ('Promoted assertion: ' + assertion.predicate),
    remedy: o.remedy || assertion.rationale || '',
    provenance: { origin: 'agent_proposed', promotedFrom: assertion.id, rationale: assertion.rationale },
  });

  const parts = String(next.packVersion).split('.');
  parts[1] = String(Number(parts[1] || 0) + 1);
  parts[2] = '0';
  next.packVersion = parts.join('.');
  next.changelog = (next.changelog || []).concat([{
    version: next.packVersion,
    note: 'Promoted agent-proposed assertion ' + assertion.id + ' as ' + id + ' (' + assertion.predicate + ').',
  }]);
  return next;
}

module.exports = {
  compile, runAdvisory, promote,
  REGEX_ARG_WHITELIST, MAX_PROPOSALS, ALLOWED_SEVERITIES, looksLikeReDoS,
};
