'use strict';
/**
 * CLAIM EXTRACTION + EVIDENCE BINDING -- the heart of the content-quality check.
 *
 * The dominant failure mode of AI-written clinical content is not bad grammar
 * and not jargon. It is a number that no sensor ever produced. A report that
 * says "your haemoglobin is 9.2 g/dL" when no haemoglobin measurement exists in
 * the episode is fluent, well-structured, perfectly readable -- and dangerous.
 * Every readability-and-tone checker on earth passes it.
 *
 * So this module treats prose as a set of CLAIMS and demands that each one BIND
 * to a piece of evidence the system actually holds. Unbound numeric claim =>
 * ungrounded. Bound to a low-fidelity estimator but stated as fact => overclaim.
 *
 * It plugs straight into the evidence envelopes the platform already emits
 * (aegis/envelopes.js `evidence.v1`, with its `fidelity` tier and
 * `provenance`), so grounding is checked against the same objects the
 * diagnostic tools produced -- not against a re-description of them.
 *
 * Everything here is pure and deterministic: same text + same evidence set =>
 * same claim list, same binding, same coverage ratio, forever.
 */

var UNIT_ALIASES = {
  'mmhg': 'mmHg', 'mm hg': 'mmHg', 'mm/hg': 'mmHg',
  '%': '%', 'percent': '%', 'pct': '%',
  'bpm': 'bpm', 'beats/min': 'bpm', 'beats per minute': 'bpm',
  'mg/dl': 'mg/dL', 'mgdl': 'mg/dL',
  'g/dl': 'g/dL', 'gdl': 'g/dL', 'gm/dl': 'g/dL',
  'mmol/l': 'mmol/L', 'mmol': 'mmol/L',
  'kg': 'kg', 'kgs': 'kg', 'lb': 'lb', 'lbs': 'lb',
  'cm': 'cm', 'mm': 'mm', 'm': 'm',
  'ml': 'mL', 'l/min': 'L/min',
  // Single-letter aliases ('c', 'f', 'm', 's') are deliberately ABSENT: they
  // false-positive inside identifiers ("HbA1c" would read as 1 degC) and the
  // recall they buy is not worth a wrong claim in a clinical certificate.
  'celsius': 'degC', 'degc': 'degC',
  'fahrenheit': 'degF', 'degf': 'degF',
  'db': 'dB', 'hz': 'Hz', 'ms': 'ms',
  'ratio': 'ratio', 'iu/l': 'IU/L', 'u/l': 'IU/L',
};

// Longest-first so "mm hg" wins over "mm".
var UNIT_PATTERN = Object.keys(UNIT_ALIASES)
  .sort(function (a, b) { return b.length - a.length || (a < b ? -1 : 1); })
  .map(function (u) { return u.replace(/[.*+?^${}()|[\]\\\/]/g, '\\$&'); })
  .join('|');

function normalizeUnit(raw) {
  if (!raw) return null;
  var k = String(raw).toLowerCase().trim().replace(/°/g, 'deg');
  return UNIT_ALIASES[k] || null;
}

/** Default numeric tolerances per unit; overridable from the policy pack. */
var DEFAULT_TOLERANCE = {
  mmHg: 2, '%': 1, bpm: 2, 'mg/dL': 2, 'g/dL': 0.2,
  'mmol/L': 0.2, kg: 0.5, degC: 0.2, _relative: 0.02,
};

function toleranceFor(unit, table) {
  var t = table || DEFAULT_TOLERANCE;
  if (unit && t[unit] !== undefined) return { abs: t[unit], rel: null };
  var rel = t._relative !== undefined ? t._relative : DEFAULT_TOLERANCE._relative;
  return { abs: null, rel: rel };
}

/**
 * Spans that are NOT clinical claims: durations, dates, list ordinals,
 * page/section refs, ages, money, and anything the pack tells us to ignore.
 * Kept as a pack-overridable list because "what counts as a claim" is exactly
 * the part that differs between a clinic and a law firm -- the engine stays
 * generic, the pack carries the domain.
 */
var DEFAULT_IGNORE = [
  '\\b\\d+\\s*(?:business\\s+)?(?:second|sec|minute|min|hour|hr|day|week|month|year|yr)s?\\b',
  '\\b\\d{4}-\\d{2}-\\d{2}\\b',
  '\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}\\b',
  '(?:^|\\n)\\s*\\d{1,2}[.)]\\s',
  '\\b(?:grade|step|stage|phase|tier|version|v|section|page|fig(?:ure)?|ref)\\s*\\.?\\s*\\d+(?:\\.\\d+)?\\b',
  '\\b(?:aged?|age)\\s*\\d{1,3}\\b',
  '\\b\\d{1,3}\\s*(?:years?|yrs?)[- ]old\\b',
  '\\bQG-[A-Z0-9.\\-]+\\b',
  '\\b(?:rs|usd|inr|eur|\\$)\\s*\\d+(?:[.,]\\d+)?\\b',
];

function buildIgnoreRegex(extra) {
  var pats = DEFAULT_IGNORE.concat(extra || []);
  return new RegExp('(?:' + pats.join(')|(?:') + ')', 'gi');
}

/** Mask ignored spans with spaces so character offsets stay stable. */
function maskIgnored(text, extraIgnore) {
  var re = buildIgnoreRegex(extraIgnore);
  var out = text.split('');
  var m;
  while ((m = re.exec(text)) !== null) {
    if (m[0].length === 0) { re.lastIndex++; continue; }
    for (var i = m.index; i < m.index + m[0].length; i++) out[i] = ' ';
  }
  return out.join('');
}

/**
 * A number in prose is not automatically a claim ABOUT THE PATIENT. "A normal
 * range sits below 120/80" is a THRESHOLD statement -- it is a good thing to
 * include, and demanding that it bind to a sensor reading would punish the
 * writer for being helpful. So each numeric span is classified by the cue words
 * immediately preceding it, and only `patient` claims carry a grounding duty.
 * Thresholds still appear in the certificate, marked, so the distinction is
 * auditable rather than a silent exemption.
 */
var DEFAULT_THRESHOLD_CUES = [
  'below', 'above', 'under', 'over', 'less than', 'greater than', 'more than',
  'normal range', 'reference range', 'normal is', 'target', 'healthy range',
  'ideal', 'up to', 'at least', 'between', 'exceeds', 'threshold', 'cut-off',
  'cutoff', 'guideline', 'anything past', 'starts at', 'considered high',
];

function classifyKind(text, offset, cues, windowChars) {
  var list = (cues && cues.length) ? cues : DEFAULT_THRESHOLD_CUES;
  var win = windowChars || 18;
  var start = Math.max(0, offset - win);
  var before = text.slice(start, offset).toLowerCase();
  for (var i = 0; i < list.length; i++) {
    if (before.indexOf(String(list[i]).toLowerCase()) >= 0) return 'threshold';
  }
  return 'patient';
}

function sentenceIndexOf(text, offset) {
  // Count sentence terminators before `offset`. Cheap, deterministic, and good
  // enough to attribute a claim to a sentence for hedge-proximity checks.
  var n = 0;
  for (var i = 0; i < offset && i < text.length; i++) {
    var c = text[i];
    if (c === '.' || c === '!' || c === '?' || c === '\n') n++;
  }
  return n;
}

function sentenceAround(text, offset) {
  var start = 0, end = text.length;
  for (var i = offset; i >= 0; i--) {
    var c = text[i];
    if (c === '.' || c === '!' || c === '?' || c === '\n') { start = i + 1; break; }
  }
  for (var j = offset; j < text.length; j++) {
    var d = text[j];
    if (d === '.' || d === '!' || d === '?' || d === '\n') { end = j; break; }
  }
  return text.slice(start, end).trim();
}

/**
 * Extract numeric claims. Two passes, in this order:
 *   1. paired readings  ("128/84 mmHg")  -> two claims, systolic + diastolic
 *   2. single readings   ("9.2 g/dL", "72 bpm", "HbA1c of 6.4%")
 * Consumed spans are masked between passes so nothing is double-counted.
 */
function extractClaims(text, opts) {
  var o = opts || {};
  var claims = [];
  var cues = o.thresholdCues || DEFAULT_THRESHOLD_CUES;
  var cueWindow = o.thresholdCueWindow || 18;
  var working = maskIgnored(text, o.ignorePatterns);

  function consume(str, start, len) {
    var arr = str.split('');
    for (var i = start; i < start + len; i++) arr[i] = ' ';
    return arr.join('');
  }

  // --- pass 1: paired readings -------------------------------------------
  // Leading group is an explicit "not glued to a letter/digit" guard instead of
  // a lookbehind, because Dart's RegExp lookbehind support is not something a
  // cross-runtime parity guarantee should rest on.
  var pairRe = new RegExp('(^|[^A-Za-z0-9.])(\\d{2,3})\\s*(?:/|over)\\s*(\\d{2,3})\\s*(' + UNIT_PATTERN + ')?(?![A-Za-z0-9])', 'gi');
  var m;
  var pairHits = [];
  while ((m = pairRe.exec(working)) !== null) {
    var unit = normalizeUnit(m[4]) || 'mmHg';
    var at = m.index + m[1].length;
    pairHits.push({ index: at, len: m[0].length - m[1].length, a: m[2], b: m[3], unit: unit, raw: m[0].slice(m[1].length).trim() });
  }
  for (var p = 0; p < pairHits.length; p++) {
    var h = pairHits[p];
    working = consume(working, h.index, h.len);
    var pairKind = classifyKind(text, h.index, cues, cueWindow);
    claims.push({
      value: Number(h.a), unit: h.unit, raw: h.raw, role: 'systolic', kind: pairKind,
      offset: h.index, sentence: sentenceIndexOf(text, h.index),
      sentenceText: sentenceAround(text, h.index),
    });
    claims.push({
      value: Number(h.b), unit: h.unit, raw: h.raw, role: 'diastolic', kind: pairKind,
      offset: h.index, sentence: sentenceIndexOf(text, h.index),
      sentenceText: sentenceAround(text, h.index),
    });
  }

  // --- pass 2: single readings -------------------------------------------
  // Trailing guard is (?![A-Za-z]) rather than \b so that a unit ending in a
  // non-word char ("6.8%.") still matches -- \b never fires between '%' and '.'.
  var singleRe = new RegExp('(^|[^A-Za-z0-9.])(\\d+(?:\\.\\d+)?)\\s*(' + UNIT_PATTERN + ')(?![A-Za-z])', 'gi');
  var singleHits = [];
  while ((m = singleRe.exec(working)) !== null) {
    var sAt = m.index + m[1].length;
    singleHits.push({ index: sAt, len: m[0].length - m[1].length, value: Number(m[2]), unit: normalizeUnit(m[3]), raw: m[0].slice(m[1].length).trim() });
  }
  for (var s2 = 0; s2 < singleHits.length; s2++) {
    var sh = singleHits[s2];
    claims.push({
      value: sh.value, unit: sh.unit, raw: sh.raw, role: null,
      kind: classifyKind(text, sh.index, cues, cueWindow),
      offset: sh.index, sentence: sentenceIndexOf(text, sh.index),
      sentenceText: sentenceAround(text, sh.index),
    });
  }

  // --- pass 3: label-anchored bare numbers ("haemoglobin of 9.2") --------
  // Only fires for labels the pack declares, so a stray "3" in prose is not
  // promoted to a clinical claim.
  var labels = o.bareNumberLabels || [];
  for (var li = 0; li < labels.length; li++) {
    var lab = labels[li];
    var labRe = new RegExp('\\b' + lab.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') +
      '\\b[^\\n\\d]{0,24}?(\\d+(?:\\.\\d+)?)', 'gi');
    while ((m = labRe.exec(working)) !== null) {
      var already = false;
      for (var ci = 0; ci < claims.length; ci++) {
        if (Math.abs(claims[ci].offset - m.index) < m[0].length + 4 &&
            claims[ci].value === Number(m[1])) { already = true; break; }
      }
      if (already) continue;
      claims.push({
        value: Number(m[1]), unit: null, raw: m[0].trim(), role: lab.toLowerCase(),
        kind: classifyKind(text, m.index, cues, cueWindow),
        offset: m.index, sentence: sentenceIndexOf(text, m.index),
        sentenceText: sentenceAround(text, m.index),
      });
    }
  }

  // Deterministic order: by offset, then value, then role.
  claims.sort(function (a, b) {
    if (a.offset !== b.offset) return a.offset - b.offset;
    if (a.value !== b.value) return a.value - b.value;
    return String(a.role) < String(b.role) ? -1 : 1;
  });
  return claims;
}

/** Flatten an evidence envelope list into bindable numeric facts. */
function evidenceFacts(evidence) {
  var facts = [];
  var list = evidence || [];
  for (var i = 0; i < list.length; i++) {
    var e = list[i] || {};
    var base = {
      toolId: e.toolId || e.id || ('evidence[' + i + ']'),
      modality: e.modality || null,
      fidelity: e.fidelity || 'unknown',
      provenance: e.provenance || {},
    };
    function push(label, value, unit) {
      if (value === null || value === undefined) return;
      var n = Number(value);
      if (!Number.isFinite(n)) return;
      facts.push({
        toolId: base.toolId, modality: base.modality, fidelity: base.fidelity,
        provenance: base.provenance, label: String(label || '').toLowerCase(),
        value: n, unit: normalizeUnit(unit) || (unit || null),
      });
    }
    push(e.label || e.finding || e.modality, e.value, e.unit);
    var sub = e.findings || [];
    for (var k = 0; k < sub.length; k++) {
      var f = sub[k] || {};
      push(f.label || f.name || f.key, f.value, f.unit);
    }
  }
  facts.sort(function (a, b) {
    if (a.toolId !== b.toolId) return a.toolId < b.toolId ? -1 : 1;
    if (a.label !== b.label) return a.label < b.label ? -1 : 1;
    return a.value - b.value;
  });
  return facts;
}

function withinTolerance(claimValue, factValue, unit, table) {
  var tol = toleranceFor(unit, table);
  var d = Math.abs(claimValue - factValue);
  if (tol.abs !== null) return d <= tol.abs + 1e-9;
  var scale = Math.max(Math.abs(factValue), 1e-9);
  return d / scale <= tol.rel + 1e-12;
}

/**
 * Bind claims to evidence facts.
 * matchKind: 'unit_value' (strongest) > 'label_value' > 'value_only' > null.
 */
function bindClaims(claims, facts, opts) {
  var o = opts || {};
  var table = o.tolerances || DEFAULT_TOLERANCE;
  var bound = [];
  for (var i = 0; i < claims.length; i++) {
    var c = claims[i];
    var best = null;
    for (var j = 0; j < facts.length; j++) {
      var f = facts[j];
      if (!withinTolerance(c.value, f.value, c.unit || f.unit, table)) continue;
      var kind = null;
      if (c.unit && f.unit && c.unit === f.unit) kind = 'unit_value';
      else if (c.role && f.label && f.label.indexOf(c.role) >= 0) kind = 'label_value';
      else if (!c.unit && !f.unit) kind = 'value_only';
      else if (o.allowCrossUnitValueMatch) kind = 'value_only';
      if (!kind) continue;
      var rank = { unit_value: 3, label_value: 2, value_only: 1 }[kind];
      if (!best || rank > best.rank) best = { fact: f, kind: kind, rank: rank };
    }
    bound.push({
      value: c.value, unit: c.unit, raw: c.raw, role: c.role,
      kind: c.kind || 'patient',
      sentence: c.sentence, sentenceText: c.sentenceText,
      boundTo: best ? best.fact.toolId : null,
      matchKind: best ? best.kind : null,
      fidelity: best ? best.fact.fidelity : null,
      modality: best ? best.fact.modality : null,
    });
  }
  return bound;
}

/** Coverage is measured over PATIENT claims only; thresholds carry no duty. */
function coverage(boundClaims) {
  var total = 0, n = 0;
  for (var i = 0; i < boundClaims.length; i++) {
    if ((boundClaims[i].kind || 'patient') !== 'patient') continue;
    total++;
    if (boundClaims[i].boundTo) n++;
  }
  if (total === 0) return 1;
  return n / total;
}

function patientClaims(boundClaims) {
  var out = [];
  for (var i = 0; i < boundClaims.length; i++) {
    if ((boundClaims[i].kind || 'patient') === 'patient') out.push(boundClaims[i]);
  }
  return out;
}

module.exports = {
  UNIT_ALIASES: UNIT_ALIASES, DEFAULT_TOLERANCE: DEFAULT_TOLERANCE,
  DEFAULT_IGNORE: DEFAULT_IGNORE,
  normalizeUnit: normalizeUnit, maskIgnored: maskIgnored,
  extractClaims: extractClaims, evidenceFacts: evidenceFacts,
  bindClaims: bindClaims, coverage: coverage, patientClaims: patientClaims,
  classifyKind: classifyKind, DEFAULT_THRESHOLD_CUES: DEFAULT_THRESHOLD_CUES,
  sentenceAround: sentenceAround,
};
