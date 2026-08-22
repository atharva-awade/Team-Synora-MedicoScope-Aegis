'use strict';
/**
 * Canonical serialization + hashing for the Quality Gate.
 *
 * Determinism is the product here, so this file has exactly one job: turn a
 * value into ONE byte string, always. Every rule in the engine hashes through
 * these functions, and the Dart port (lib/services/quality/qg_canonical.dart)
 * reproduces them byte-for-byte. The parity harness proves it.
 *
 * Rules of canonical form:
 *   - object keys sorted by UTF-16 code unit (JS default sort / Dart compareTo)
 *   - no insignificant whitespace
 *   - numbers emitted via `num()` (fixed 6-dp, negative-zero normalized) so
 *     0.1+0.2 and 0.30000000000000004 cannot fork a hash across runtimes
 *   - undefined is dropped from objects, becomes null in arrays
 *   - NO clock, NO locale, NO randomness anywhere in this module
 */
const crypto = require('crypto');

/**
 * Half-up rounding written out explicitly rather than via Math.round.
 * Math.round and Dart's num.round() disagree on exact negative halves
 * (JS gives -0 for -0.5, Dart gives -1), and a cross-runtime hash cannot rest
 * on a difference like that. floor(x + 0.5) is the same expression in both
 * languages, so parity is structural instead of coincidental.
 */
function roundHalfUp(x) {
  return Math.floor(x + 0.5);
}

/** Fixed-precision number form. 6 dp is well inside float64 exactness here. */
function num(n) {
  if (typeof n !== 'number' || !Number.isFinite(n)) return 'null';
  const r = roundHalfUp(n * 1e6) / 1e6;
  const s = (Object.is(r, -0) ? 0 : r).toFixed(6);
  // strip trailing zeros but keep at least one decimal digit
  return s.replace(/(\.\d*?)0+$/, '$1').replace(/\.$/, '.0');
}

function canonical(value) {
  if (value === null || value === undefined) return 'null';
  const t = typeof value;
  if (t === 'number') return num(value);
  if (t === 'boolean') return value ? 'true' : 'false';
  if (t === 'string') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (t === 'object') {
    const keys = Object.keys(value).filter((k) => value[k] !== undefined).sort();
    return '{' + keys.map((k) => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
  }
  return 'null';
}

function sha256Hex(s) {
  return crypto.createHash('sha256').update(s, 'utf8').digest('hex');
}

function digest(value) {
  return sha256Hex(canonical(value));
}

/**
 * Human-transcribable certificate id: Crockford base32 of the first 50 bits of
 * the digest, grouped 5-5. Excludes I, L, O, U so it survives being read aloud
 * on a demo stage or typed off a printed PDF.
 */
const B32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
function shortId(hexDigest) {
  let out = '';
  for (let i = 0; i < 10; i++) {
    // 5 bits per char, walked deterministically over the hex string
    const nibbleHi = parseInt(hexDigest[i], 16);
    const nibbleLo = parseInt(hexDigest[i + 10], 16);
    out += B32[(nibbleHi * 2 + (nibbleLo & 1)) % 32];
  }
  return out.slice(0, 5) + '-' + out.slice(5);
}

/** Round to 4 dp identically in JS and Dart (used for every published score). */
function score4(x) {
  const r = roundHalfUp(x * 10000) / 10000;
  return Object.is(r, -0) ? 0 : r;
}

module.exports = { canonical, digest, sha256Hex, shortId, num, score4, roundHalfUp };
