'use strict';
/**
 * PREDICATE REGISTRY -- the only executable surface of the Quality Gate.
 *
 * Design rule: the POLICY PACK IS DATA, NOT CODE. A pack may reference these
 * predicates by id and pass them arguments; it can never inject logic. There is
 * no eval, no Function constructor, no regex-from-pack-without-a-flag-audit.
 * That is what lets an untrusted party (or an LLM critic) propose a new rule
 * without being able to propose new behaviour.
 *
 * Every predicate is:
 *   PURE          - no clock, no I/O, no randomness, no module state
 *   TOTAL         - never throws on malformed content; returns ok:false instead
 *   PORTABLE      - the Dart port in lib/services/quality/ implements the same
 *                   ids with the same semantics, and harness/parity.js proves it
 *
 * Signature: fn(ctx, args) -> { ok: boolean, detail: string, data: object }
 *   `data` participates in the verdict digest; `detail` does NOT (it is prose
 *   for humans, and cross-runtime number formatting must never fork a hash).
 */

var text = require('./text');
var claimsLib = require('./claims');

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function lex(ctx, name) {
  var lexicons = (ctx.pack && ctx.pack.lexicons) || {};
  var v = lexicons[name];
  return Array.isArray(v) ? v : [];
}

function lowerText(ctx) { return ctx.lowerText; }

function anyTermPresent(hay, terms) {
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && hay.indexOf(String(terms[i]).toLowerCase()) >= 0) return terms[i];
  }
  return null;
}

function allTermsPresent(hay, terms) {
  var missing = [];
  for (var i = 0; i < terms.length; i++) {
    if (hay.indexOf(String(terms[i]).toLowerCase()) < 0) missing.push(terms[i]);
  }
  return missing;
}

function fieldValue(content, path) {
  var parts = String(path).split('.');
  var cur = content;
  for (var i = 0; i < parts.length; i++) {
    if (cur === null || cur === undefined) return undefined;
    cur = cur[parts[i]];
  }
  return cur;
}

function isEmptyValue(v) {
  if (v === null || v === undefined) return true;
  if (typeof v === 'string') return v.trim().length === 0;
  if (Array.isArray(v)) return v.length === 0;
  if (typeof v === 'object') return Object.keys(v).length === 0;
  return false;
}

var P = {};

// ---------------------------------------------------------------------------
// STRUCTURE
// ---------------------------------------------------------------------------

P.fieldsPresent = function (ctx, args) {
  var fields = (args && args.fields) || [];
  var missing = [];
  for (var i = 0; i < fields.length; i++) {
    if (isEmptyValue(fieldValue(ctx.content, fields[i]))) missing.push(fields[i]);
  }
  missing.sort();
  return {
    ok: missing.length === 0,
    detail: missing.length ? 'missing: ' + missing.join(', ') : 'all required fields present',
    data: { missing: missing, requiredCount: fields.length },
  };
};

P.minWords = function (ctx, args) {
  var min = (args && args.min) || 0;
  var field = args && args.field;
  var src = field ? String(fieldValue(ctx.content, field) || '') : ctx.text;
  var n = text.words(src).length;
  return {
    ok: n >= min,
    detail: n + ' words (min ' + min + ')',
    data: { words: n, min: min },
  };
};

/** Leftover authoring scaffolding. Domain-neutral and brutally effective. */
P.placeholderAbsent = function (ctx, args) {
  var tokens = (args && args.tokens) || lex(ctx, 'placeholders');
  var found = [];
  var hay = lowerText(ctx);
  for (var i = 0; i < tokens.length; i++) {
    if (hay.indexOf(String(tokens[i]).toLowerCase()) >= 0) found.push(tokens[i]);
  }
  found.sort();
  return {
    ok: found.length === 0,
    detail: found.length ? 'placeholder tokens: ' + found.join(', ') : 'no placeholder tokens',
    data: { found: found },
  };
};

/** Copy-paste padding: the same sentence emitted more than `maxRepeats` times. */
P.noDuplicateSentences = function (ctx, args) {
  var maxRepeats = (args && args.maxRepeats) !== undefined ? args.maxRepeats : 1;
  var minWordsToCount = (args && args.minWords) || 5;
  var counts = {};
  for (var i = 0; i < ctx.sentences.length; i++) {
    var s = ctx.sentences[i].toLowerCase().replace(/[^a-z0-9 ]/g, '').replace(/\s+/g, ' ').trim();
    if (text.words(s).length < minWordsToCount) continue;
    counts[s] = (counts[s] || 0) + 1;
  }
  var offenders = Object.keys(counts).filter(function (k) { return counts[k] > maxRepeats; }).sort();
  return {
    ok: offenders.length === 0,
    detail: offenders.length ? offenders.length + ' repeated sentence(s)' : 'no repeated sentences',
    data: { repeatedCount: offenders.length, maxRepeats: maxRepeats },
  };
};

/** Truncated generation: dangling connective, unbalanced bracket, trailing ellipsis. */
/**
 * Truncation is a property of the BODY, not of the concatenated document: the
 * recommendations and disclaimer are appended after the body, so checking the
 * joined text would let a clean disclaimer hide a body that stopped mid-word.
 */
P.noTruncation = function (ctx) {
  var t = String(ctx.body || '').trim();
  if (t.length === 0) return { ok: false, detail: 'empty body', data: { reason: 'empty' } };
  var reasons = [];
  if (/(\.\.\.|…)$/.test(t)) reasons.push('ellipsis_end');
  if (/\b(and|or|but|with|the|a|an|of|to|for|because|which|that|while|if)$/i.test(t)) reasons.push('dangling_connective');
  if (!/[.!?)\]"']$/.test(t)) reasons.push('no_terminal_punctuation');
  var open = (t.match(/[([{]/g) || []).length;
  var close = (t.match(/[)\]}]/g) || []).length;
  if (open !== close) reasons.push('unbalanced_brackets');
  reasons.sort();
  return {
    ok: reasons.length === 0,
    detail: reasons.length ? reasons.join(', ') : 'body terminates cleanly',
    data: { reasons: reasons },
  };
};

// ---------------------------------------------------------------------------
// READABILITY
// ---------------------------------------------------------------------------

P.readabilityGradeAtMost = function (ctx, args) {
  var max = (args && args.max) !== undefined ? args.max : 12;
  var g = ctx.read.fkGrade;
  return {
    ok: g <= max,
    detail: 'Flesch-Kincaid grade ' + g + ' (max ' + max + ')',
    data: { fkGrade: g, max: max, band: text.gradeBand(g) },
  };
};

P.readingEaseAtLeast = function (ctx, args) {
  var min = (args && args.min) !== undefined ? args.min : 50;
  var e = ctx.read.readingEase;
  return { ok: e >= min, detail: 'reading ease ' + e + ' (min ' + min + ')', data: { readingEase: e, min: min } };
};

P.sentenceLengthAtMost = function (ctx, args) {
  var maxWords = (args && args.maxWords) || 28;
  var allowed = (args && args.allowed) || 0;
  var over = 0;
  for (var i = 0; i < ctx.sentences.length; i++) {
    if (text.words(ctx.sentences[i]).length > maxWords) over++;
  }
  return {
    ok: over <= allowed,
    detail: over + ' sentence(s) over ' + maxWords + ' words (allowed ' + allowed + ')',
    data: { overLimit: over, maxWords: maxWords, allowed: allowed, longest: ctx.read.longestSentenceWords },
  };
};

/**
 * Jargon must be GLOSSED, not banned. A term counts as glossed when a plain
 * gloss appears within `window` characters of it -- which is what a real
 * clinician does when writing for a patient.
 */
P.jargonGlossed = function (ctx, args) {
  var maxUnglossed = (args && args.maxUnglossed) !== undefined ? args.maxUnglossed : 0;
  var win = (args && args.window) || 60;
  var map = (ctx.pack && ctx.pack.lexicons && ctx.pack.lexicons.jargon) || {};
  var hay = lowerText(ctx);
  var unglossed = [];
  var terms = Object.keys(map).sort();
  for (var i = 0; i < terms.length; i++) {
    var term = terms[i];
    var at = hay.indexOf(term);
    if (at < 0) continue;
    var gloss = String(map[term] || '').toLowerCase();
    var around = hay.slice(Math.max(0, at - win), Math.min(hay.length, at + term.length + win));
    if (gloss && around.indexOf(gloss) >= 0) continue;
    unglossed.push(term);
  }
  return {
    ok: unglossed.length <= maxUnglossed,
    detail: unglossed.length ? 'unglossed: ' + unglossed.join(', ') : 'all clinical terms glossed',
    data: { unglossed: unglossed, maxUnglossed: maxUnglossed },
  };
};

/** Deterministic passive-voice proxy: "be" verb + past participle. */
P.passiveVoiceAtMost = function (ctx, args) {
  var maxRatio = (args && args.maxRatio) !== undefined ? args.maxRatio : 0.4;
  var re = /\b(?:is|are|was|were|be|been|being)\s+(?:[a-z]+ly\s+)?[a-z]+(?:ed|en)\b/g;
  var hits = (lowerText(ctx).match(re) || []).length;
  var n = Math.max(1, ctx.sentences.length);
  var ratio = Math.floor((hits / n) * 10000 + 0.5) / 10000;
  return {
    ok: ratio <= maxRatio,
    detail: 'passive ratio ' + ratio + ' (max ' + maxRatio + ')',
    data: { passiveHits: hits, sentences: ctx.sentences.length, ratio: ratio, maxRatio: maxRatio },
  };
};

// ---------------------------------------------------------------------------
// SAFETY
// ---------------------------------------------------------------------------

P.escalationPresentWhenRisk = function (ctx, args) {
  var risks = (args && args.risks) || ['high', 'critical'];
  var terms = (args && args.lexicon) ? lex(ctx, args.lexicon) : lex(ctx, 'escalation');
  var risk = String((ctx.content.riskLevel || '')).toLowerCase();
  if (risks.indexOf(risk) < 0) {
    return { ok: true, detail: 'risk "' + risk + '" does not require escalation wording', data: { applicable: false, risk: risk } };
  }
  var hay = lowerText(ctx) + ' ' + ctx.recommendationsText;
  var hit = anyTermPresent(hay, terms);
  return {
    ok: !!hit,
    detail: hit ? 'escalation phrase present: "' + hit + '"' : 'no escalation phrase for ' + risk + ' risk',
    data: { applicable: true, risk: risk, matched: hit || null },
  };
};

P.disclaimerPresent = function (ctx, args) {
  var terms = (args && args.anyOf) || lex(ctx, 'disclaimer');
  var hay = lowerText(ctx) + ' ' + ctx.recommendationsText + ' ' + String(ctx.content.disclaimer || '').toLowerCase();
  var hit = anyTermPresent(hay, terms);
  return {
    ok: !!hit,
    detail: hit ? 'disclaimer matched "' + hit + '"' : 'no disclosure or scope phrase matched',
    data: { matched: hit || null },
  };
};

/** A screening product may not speak in certainties. */
P.absolutistLanguageAbsent = function (ctx, args) {
  var terms = (args && args.lexicon) ? lex(ctx, args.lexicon) : lex(ctx, 'absolutes');
  var hay = lowerText(ctx) + ' ' + ctx.recommendationsText;
  var found = [];
  for (var i = 0; i < terms.length; i++) {
    if (hay.indexOf(String(terms[i]).toLowerCase()) >= 0) found.push(terms[i]);
  }
  found.sort();
  return {
    ok: found.length === 0,
    detail: found.length ? 'absolutist phrasing: ' + found.join(', ') : 'no absolutist phrasing',
    data: { found: found },
  };
};

/**
 * SCOPE GUARD. A screening tool must not emit therapy. This is the check that
 * stops a helpful-sounding LLM from prescribing, and it is the reason the gate
 * belongs on the finalize path rather than in a linter.
 */
P.outOfScopeAdviceAbsent = function (ctx, args) {
  var terms = (args && args.lexicon) ? lex(ctx, args.lexicon) : lex(ctx, 'prescriptive');
  var hay = lowerText(ctx) + ' ' + ctx.recommendationsText;
  var found = [];
  for (var i = 0; i < terms.length; i++) {
    if (hay.indexOf(String(terms[i]).toLowerCase()) >= 0) found.push(terms[i]);
  }
  // Dosage pattern: a number immediately followed by a drug unit.
  // Trailing guard excludes compound clinical units -- "9.2 g/dL" is a lab
  // result, not a dose, and mistaking the two makes the scope guard useless.
  if (/\b\d+(?:\.\d+)?\s*(?:mg|mcg|ug|iu)(?![A-Za-z\/])/i.test(ctx.text) ||
      /\b\d+(?:\.\d+)?\s*(?:g|ml)(?![A-Za-z\/])\s*(?:of\s+)?[a-z]{4,}/i.test(ctx.text)) {
    found.push('dosage_expression');
  }
  found.sort();
  return {
    ok: found.length === 0,
    detail: found.length ? 'out-of-scope therapeutic advice: ' + found.join(', ') : 'stays within screening scope',
    data: { found: found },
  };
};

P.piiAbsent = function (ctx, args) {
  var patterns = (args && args.patterns) || [
    '\\b[0-9]{12}\\b',
    '\\b[0-9]{4}[ -][0-9]{4}[ -][0-9]{4}\\b',
    '\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b',
    '\\b(?:\\+?[0-9]{1,3}[ -]?)?[0-9]{10}\\b',
  ];
  var found = [];
  for (var i = 0; i < patterns.length; i++) {
    var re = new RegExp(patterns[i], 'g');
    if (re.test(ctx.text)) found.push(patterns[i]);
  }
  found.sort();
  return {
    ok: found.length === 0,
    detail: found.length ? found.length + ' PII-shaped span(s) in body' : 'no PII-shaped spans in body',
    data: { matchedPatterns: found.length },
  };
};

P.confidenceCalibrated = function (ctx, args) {
  var floor = (args && args.floor) !== undefined ? args.floor : 0.45;
  var risks = (args && args.risks) || ['high', 'critical'];
  var risk = String(ctx.content.riskLevel || '').toLowerCase();
  var conf = ctx.content.confidence;
  if (risks.indexOf(risk) < 0) {
    return { ok: true, detail: 'calibration gate not applicable at "' + risk + '"', data: { applicable: false } };
  }
  if (conf === null || conf === undefined) {
    return { ok: false, detail: 'no confidence declared on a ' + risk + '-risk output', data: { applicable: true, confidence: null, floor: floor } };
  }
  // Deliberately NOT the general hedge lexicon. A screening disclaimer is not a
  // statement about THIS result's reliability, and conflating the two lets every
  // report with boilerplate at the bottom dodge the calibration rule.
  var disclosureLex = (args && args.lexicon) ? lex(ctx, args.lexicon) : lex(ctx, 'uncertaintyDisclosure');
  var disclosed = anyTermPresent(lowerText(ctx), disclosureLex);
  var ok = conf >= floor || !!disclosed;
  return {
    ok: ok,
    detail: 'confidence ' + conf + ' vs floor ' + floor + (disclosed ? ' (uncertainty disclosed)' : ' (no uncertainty disclosure)'),
    data: { applicable: true, confidence: conf, floor: floor, disclosed: !!disclosed },
  };
};

// ---------------------------------------------------------------------------
// ACTIONABILITY
// ---------------------------------------------------------------------------

P.recommendationsAtLeast = function (ctx, args) {
  var min = (args && args.min) || 1;
  var n = (ctx.content.recommendations || []).length;
  return { ok: n >= min, detail: n + ' recommendation(s) (min ' + min + ')', data: { count: n, min: min } };
};

P.timeframePresent = function (ctx, args) {
  var hay = lowerText(ctx) + ' ' + ctx.recommendationsText;
  var re = new RegExp((args && args.pattern) ||
    '\\b(?:within|in|after|every|next|by)\\s+(?:the\\s+)?(?:\\d+|one|two|three|four|five|six|seven|ten|twelve|fourteen|twenty)\\s*' +
    '(?:business\\s+)?(?:hour|day|week|month|year)s?\\b|\\b(?:immediately|same\\s+day|today|now|urgently)\\b', 'i');
  var hit = re.test(hay);
  return { ok: hit, detail: hit ? 'explicit timeframe present' : 'no explicit follow-up timeframe', data: { present: hit } };
};

P.ownerPresent = function (ctx, args) {
  var terms = (args && args.lexicon) ? lex(ctx, args.lexicon) : lex(ctx, 'owners');
  var hay = lowerText(ctx) + ' ' + ctx.recommendationsText;
  var hit = anyTermPresent(hay, terms);
  return { ok: !!hit, detail: hit ? 'named actor: "' + hit + '"' : 'no named actor for the next step', data: { matched: hit || null } };
};

P.imperativePresent = function (ctx, args) {
  var terms = (args && args.lexicon) ? lex(ctx, args.lexicon) : lex(ctx, 'imperatives');
  var recs = ctx.content.recommendations || [];
  var n = 0;
  for (var i = 0; i < recs.length; i++) {
    var first = String(recs[i] || '').trim().toLowerCase().split(/[^a-z]+/)[0];
    if (terms.indexOf(first) >= 0) n++;
  }
  var min = (args && args.min) || 1;
  return { ok: n >= min, detail: n + ' actionable recommendation(s)', data: { actionable: n, min: min, total: recs.length } };
};

// ---------------------------------------------------------------------------
// GROUNDING  (the dimension that actually catches invented clinical content)
// ---------------------------------------------------------------------------

P.evidenceDeclared = function (ctx, args) {
  var min = (args && args.min) || 1;
  var n = (ctx.content.evidence || []).length;
  return { ok: n >= min, detail: n + ' evidence envelope(s)', data: { count: n, min: min } };
};

P.provenanceDeclared = function (ctx) {
  var ev = ctx.content.evidence || [];
  var bad = [];
  for (var i = 0; i < ev.length; i++) {
    var e = ev[i] || {};
    var pv = e.provenance || {};
    if (e.fidelity === 'real' && !pv.model && !pv.source) bad.push(e.toolId || ('evidence[' + i + ']'));
  }
  bad.sort();
  return {
    ok: bad.length === 0,
    detail: bad.length ? 'real-fidelity evidence without provenance: ' + bad.join(', ') : 'provenance declared where required',
    data: { missingProvenance: bad },
  };
};

P.groundingCoverageAtLeast = function (ctx, args) {
  var min = (args && args.min) !== undefined ? args.min : 0.9;
  var cov = Math.floor(ctx.groundingCoverage * 10000 + 0.5) / 10000;
  return {
    ok: cov >= min - 1e-9,
    detail: 'grounding coverage ' + cov + ' (min ' + min + ')',
    data: { coverage: cov, min: min, claims: claimsLib.patientClaims(ctx.boundClaims).length },
  };
};

/**
 * THE flagship check. Any numeric claim in the prose that binds to no evidence
 * the system holds is an invented measurement. `maxUnbound: 0` makes it fatal.
 */
P.noUngroundedClaims = function (ctx, args) {
  var maxUnbound = (args && args.maxUnbound) !== undefined ? args.maxUnbound : 0;
  var unbound = [];
  var pc = claimsLib.patientClaims(ctx.boundClaims);
  for (var i = 0; i < pc.length; i++) {
    var c = pc[i];
    if (!c.boundTo) {
      unbound.push({
        value: c.value, unit: c.unit || null,
        raw: c.role ? c.raw + ' (' + c.role + ')' : c.raw,
      });
    }
  }
  unbound.sort(function (a, b) {
    if (a.value !== b.value) return a.value - b.value;
    if (String(a.unit) !== String(b.unit)) return String(a.unit) < String(b.unit) ? -1 : 1;
    return a.raw < b.raw ? -1 : 1;
  });
  return {
    ok: unbound.length <= maxUnbound,
    detail: unbound.length
      ? unbound.length + ' ungrounded numeric claim(s): ' + unbound.map(function (u) { return u.raw; }).join(' | ')
      : 'every numeric claim binds to evidence',
    data: { unbound: unbound, maxUnbound: maxUnbound },
  };
};

/**
 * A number produced by a heuristic estimator, stated as if measured. This is
 * the check that reads the platform's own fidelity tiers -- the gate refuses to
 * let a `heuristic` or `fabricated_scale` reading be narrated as fact.
 */
P.fidelityNoOverclaim = function (ctx, args) {
  var soft = (args && args.softFidelities) || ['partial', 'heuristic', 'fabricated_scale', 'unknown'];
  var hedges = (args && args.hedgeLexicon) ? lex(ctx, args.hedgeLexicon) : lex(ctx, 'hedges');
  var offenders = [];
  var pcl = claimsLib.patientClaims(ctx.boundClaims);
  for (var i = 0; i < pcl.length; i++) {
    var c = pcl[i];
    if (!c.boundTo || soft.indexOf(c.fidelity) < 0) continue;
    var sent = String(c.sentenceText || '').toLowerCase();
    if (anyTermPresent(sent, hedges)) continue;
    offenders.push({ raw: c.raw, toolId: c.boundTo, fidelity: c.fidelity });
  }
  offenders.sort(function (a, b) {
    if (a.toolId !== b.toolId) return a.toolId < b.toolId ? -1 : 1;
    return a.raw < b.raw ? -1 : 1;
  });
  return {
    ok: offenders.length === 0,
    detail: offenders.length
      ? offenders.length + ' unhedged claim(s) from non-validated evidence: ' +
        offenders.map(function (o) { return o.raw + '<-' + o.toolId + '(' + o.fidelity + ')'; }).join(' | ')
      : 'estimator-derived values are appropriately hedged',
    data: { offenders: offenders, softFidelities: soft.slice().sort() },
  };
};

/**
 * Internal contradiction: the stated risk label must agree with the numeric
 * risk score. A report that says "low risk" over a 0.82 score is not a wording
 * problem, it is a wrong document.
 */
P.riskLabelConsistent = function (ctx, args) {
  var bands = (args && args.bands) || {
    low: [0, 0.35], moderate: [0.35, 0.6], high: [0.6, 0.85], critical: [0.85, 1.01],
  };
  var risk = String(ctx.content.riskLevel || '').toLowerCase();
  var score = ctx.content.score;
  if (score === null || score === undefined || !bands[risk]) {
    return { ok: true, detail: 'no numeric score to cross-check', data: { applicable: false } };
  }
  var band = bands[risk];
  var ok = score >= band[0] - 1e-9 && score < band[1];
  return {
    ok: ok,
    detail: 'risk "' + risk + '" vs score ' + score + ' (band ' + band[0] + '-' + band[1] + ')',
    data: { applicable: true, risk: risk, score: score, bandLow: band[0], bandHigh: band[1] },
  };
};

/** Declared numeric pairs must not contradict each other beyond a tolerance. */
P.crossFieldConsistency = function (ctx, args) {
  var pairs = (args && args.pairs) || [];
  var violations = [];
  for (var i = 0; i < pairs.length; i++) {
    var pr = pairs[i];
    var a = Number(fieldValue(ctx.content, pr.a));
    var b = Number(fieldValue(ctx.content, pr.b));
    if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
    if (pr.rule === 'gte' && !(a >= b)) violations.push(pr.a + '<' + pr.b);
    else if (pr.rule === 'lte' && !(a <= b)) violations.push(pr.a + '>' + pr.b);
    else if (pr.rule === 'near' && Math.abs(a - b) > (pr.maxDelta || 0)) violations.push(pr.a + '~' + pr.b);
  }
  violations.sort();
  return {
    ok: violations.length === 0,
    detail: violations.length ? 'inconsistent: ' + violations.join(', ') : 'declared fields are mutually consistent',
    data: { violations: violations },
  };
};

/** Abnormal values should state the reference range they are abnormal against. */
P.referenceRangeWhenAbnormal = function (ctx, args) {
  var risks = (args && args.risks) || ['moderate', 'high', 'critical'];
  var risk = String(ctx.content.riskLevel || '').toLowerCase();
  if (risks.indexOf(risk) < 0) return { ok: true, detail: 'not applicable at "' + risk + '"', data: { applicable: false } };
  var hay = lowerText(ctx) + ' ' + ctx.recommendationsText;
  var re = /\b(?:normal|reference|target|healthy)\s+(?:range|value|level|band)\b|\b(?:below|above|between)\s+\d|\bscale of \d+\s*(?:to|-|and)\s*\d+\b|\bout of \d+\b|\bnormal (?:sits|is)\b/;
  var hit = re.test(hay);
  return {
    ok: hit,
    detail: hit ? 'reference range stated' : 'abnormal result without a stated reference range',
    data: { applicable: true, present: hit },
  };
};

// ---------------------------------------------------------------------------

/** Every predicate id the pack is allowed to name. */
function ids() { return Object.keys(P).sort(); }
function get(id) { return P[id]; }
function has(id) { return Object.prototype.hasOwnProperty.call(P, id); }

module.exports = { registry: P, ids: ids, get: get, has: has, _helpers: { fieldValue: fieldValue, isEmptyValue: isEmptyValue, anyTermPresent: anyTermPresent, allTermsPresent: allTermsPresent } };
