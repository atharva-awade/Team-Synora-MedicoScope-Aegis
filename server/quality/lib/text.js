'use strict';
/**
 * Deterministic text tokenization + real readability metrics.
 *
 * Why this file exists: the previous gate reported readability from a
 * words-per-sentence lookup table that returned hard-coded strings like
 * "Grade 6.2 (Elementary)". That is not a measurement, so it could never fail
 * and never move. Here we compute the actual Flesch-Kincaid Grade Level and
 * Flesch Reading Ease from a deterministic syllable estimator, and every
 * intermediate count is published in the certificate so the number can be
 * reproduced by hand.
 *
 * All regexes are deliberately ASCII-simple so the Dart port matches exactly.
 */

/** Normalize to one canonical text form before any measurement. */
function normalizeText(s) {
  return String(s == null ? '' : s)
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map(function (l) { return l.replace(/[ \t]+$/g, ''); })
    .join('\n')
    .trim();
}

/**
 * Sentence split on terminal punctuation. Decimals (12.5) and a small set of
 * abbreviations have their dot removed first so they cannot manufacture a
 * sentence boundary and deflate the words-per-sentence term.
 */
function sentences(text) {
  var guarded = String(text)
    // 12.5 must not read as two sentences (affects words-per-sentence).
    .replace(/(\d)\.(\d)/g, '$1$2')
    // Multi-dot abbreviations collapse to dotless forms; titles just lose the
    // trailing dot. Both are sentence-splitting artifacts only -- claim
    // extraction always runs on the ORIGINAL text, never on `guarded`.
    .replace(/\be\.g\./g, 'eg')
    .replace(/\bi\.e\./g, 'ie')
    .replace(/\bet\s*al\./g, 'et al')
    .replace(/\b(Dr|Mr|Mrs|Ms|Prof|vs|approx|No|Fig|Ref)\./g, '$1');
  return guarded
    .split(/[.!?\n]+/)
    .map(function (s) { return s.trim(); })
    .filter(function (s) { return s.length > 0; });
}

function words(text) {
  var m = String(text).match(/[A-Za-z][A-Za-z'\-]*/g);
  return m ? m : [];
}

/**
 * Syllable estimate: vowel-group heuristic with the standard corrections.
 * Chosen because it is trivially portable and stable, not because it is
 * linguistically perfect. Stability beats accuracy for a gate -- a metric that
 * drifts between runtimes cannot be a threshold.
 */
function syllables(word) {
  var w = String(word).toLowerCase().replace(/[^a-z]/g, '');
  if (w.length === 0) return 0;
  if (w.length <= 3) return 1;
  w = w.replace(/(?:[^laeiouy]es|ed|[^laeiouy]e)$/, '');
  w = w.replace(/^y/, '');
  var groups = w.match(/[aeiouy]{1,2}/g);
  var n = groups ? groups.length : 0;
  return n < 1 ? 1 : n;
}

/** Round to 2 dp identically in JS and Dart (see canonical.roundHalfUp). */
function r2(x) {
  var v = Math.floor(x * 100 + 0.5) / 100;
  return Object.is(v, -0) ? 0 : v;
}

/**
 * @returns {{wordCount:number, sentenceCount:number, syllableCount:number,
 *            polysyllables:number, fkGrade:number, readingEase:number,
 *            avgWordsPerSentence:number, longestSentenceWords:number}}
 */
function readability(text) {
  var sents = sentences(text);
  var allWords = words(text);
  var wordCount = allWords.length;
  var sentenceCount = sents.length;

  var syllableCount = 0;
  var polysyllables = 0;
  for (var i = 0; i < allWords.length; i++) {
    var s = syllables(allWords[i]);
    syllableCount += s;
    if (s >= 3) polysyllables += 1;
  }

  var longest = 0;
  for (var j = 0; j < sents.length; j++) {
    var n = words(sents[j]).length;
    if (n > longest) longest = n;
  }

  if (wordCount === 0 || sentenceCount === 0) {
    return {
      wordCount: wordCount, sentenceCount: sentenceCount,
      syllableCount: syllableCount, polysyllables: polysyllables,
      fkGrade: 0, readingEase: 0, avgWordsPerSentence: 0, longestSentenceWords: 0,
    };
  }

  var wps = wordCount / sentenceCount;
  var spw = syllableCount / wordCount;

  return {
    wordCount: wordCount,
    sentenceCount: sentenceCount,
    syllableCount: syllableCount,
    polysyllables: polysyllables,
    // Flesch-Kincaid Grade Level
    fkGrade: r2(0.39 * wps + 11.8 * spw - 15.59),
    // Flesch Reading Ease
    readingEase: r2(206.835 - 1.015 * wps - 84.6 * spw),
    avgWordsPerSentence: r2(wps),
    longestSentenceWords: longest,
  };
}

/** Band label DERIVED from the measured grade, never asserted independently. */
function gradeBand(fkGrade) {
  if (fkGrade < 6) return 'very_accessible';
  if (fkGrade < 9) return 'accessible';
  if (fkGrade < 12) return 'demanding';
  return 'specialist';
}

module.exports = {
  normalizeText: normalizeText, sentences: sentences, words: words,
  syllables: syllables, readability: readability, gradeBand: gradeBand, r2: r2,
};
