/// LOCAL PRE-FLIGHT -- deliberately NOT a verdict.
///
/// The authoritative Quality Gate runs on the server, because the rules must
/// have exactly one implementation and it must not live on the device belonging
/// to the person being audited. But a clinician typing notes wants feedback now,
/// not after a round trip, so this file provides an offline hint layer.
///
/// Three rules keep it honest, and they are the whole reason it is safe to have:
///   1. It issues NO certificate and computes NO hash. It cannot be mistaken
///      for, or presented as, a certification.
///   2. It only implements checks that need nothing but the text itself. It
///      deliberately does NOT attempt evidence binding, fidelity overclaim, or
///      risk-label consistency -- the checks that actually gate a report -- so
///      it can never imply a report is safe when the gate would block it.
///   3. Everything it returns is marked provisional in the UI.
///
/// A local hint that could be read as a pass is worse than no local hint. This
/// one is built so that it cannot be.
class QgPreflightIssue {
  final String checkId;
  final String label;
  final String detail;
  final String remedy;
  final String dimension;
  final bool ok;

  const QgPreflightIssue({
    required this.checkId,
    required this.label,
    required this.detail,
    required this.remedy,
    required this.dimension,
    required this.ok,
  });
}

class QgPreflightResult {
  final List<QgPreflightIssue> issues;
  final double localGrade;   // Flesch-Kincaid grade of the supplied text
  final int wordCount;
  final int sentenceCount;

  const QgPreflightResult({
    required this.issues,
    required this.localGrade,
    required this.wordCount,
    required this.sentenceCount,
  });

  List<QgPreflightIssue> get failures =>
      issues.where((i) => !i.ok).toList(growable: false);
  int get passedCount => issues.where((i) => i.ok).length;
  int get totalCount => issues.length;

  /// Share of LOCAL checks that pass. Never presented as the gate's score.
  double get localPassRatio =>
      issues.isEmpty ? 1.0 : passedCount / issues.length;
}

class QgPreflight {
  /// Small gloss map, used only to suggest plain-language alternatives in the
  /// redline panel. The authoritative jargon lexicon lives in the policy pack.
  static const Map<String, String> jargonGlosses = <String, String>{
    'myocardial infarction': 'heart attack',
    'hyperglycemia': 'high blood sugar',
    'hypoglycemia': 'low blood sugar',
    'dyspnea': 'shortness of breath',
    'tachycardia': 'fast heart rate',
    'bradycardia': 'slow heart rate',
    'diaphoresis': 'heavy sweating',
    'pruritus': 'itching',
    'erythema': 'redness',
    'ischemia': 'reduced blood flow',
    'arrhythmia': 'irregular heartbeat',
    'hypertension': 'high blood pressure',
    'hypotension': 'low blood pressure',
    'edema': 'swelling',
    'oedema': 'swelling',
    'anaemia': 'low red blood cell',
    'anemia': 'low red blood cell',
    'retinopathy': 'damage to the retina',
    'auscultation': 'listening to the chest',
    'bronchospasm': 'airway tightening',
    'neuropathy': 'nerve damage',
    'nephropathy': 'kidney damage',
  };

  static const List<String> placeholders = <String>[
    'todo', 'tbd', 'lorem ipsum', 'xxx', '<insert', '[insert',
    'placeholder', 'fixme', 'to be completed',
  ];

  static List<String> words(String text) => RegExp(r"[A-Za-z][A-Za-z'\-]*")
      .allMatches(text)
      .map((m) => m.group(0)!)
      .toList(growable: false);

  static List<String> sentences(String text) => text
      .replaceAllMapped(RegExp(r'(\d)\.(\d)'), (m) => '${m[1]}${m[2]}')
      .split(RegExp(r'[.!?\n]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  static int syllables(String word) {
    var w = word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (w.isEmpty) return 0;
    if (w.length <= 3) return 1;
    w = w.replaceFirst(RegExp(r'(?:[^laeiouy]es|ed|[^laeiouy]e)$'), '');
    w = w.replaceFirst(RegExp(r'^y'), '');
    final n = RegExp(r'[aeiouy]{1,2}').allMatches(w).length;
    return n < 1 ? 1 : n;
  }

  /// Flesch-Kincaid grade level. Same formula as the server, but note this is a
  /// display hint only -- the server's number is the one that gates.
  static double fkGrade(String text) {
    final ws = words(text);
    final ss = sentences(text);
    if (ws.isEmpty || ss.isEmpty) return 0;
    var syl = 0;
    for (final w in ws) {
      syl += syllables(w);
    }
    final wps = ws.length / ss.length;
    final spw = syl / ws.length;
    final g = 0.39 * wps + 11.8 * spw - 15.59;
    return (g * 100 + 0.5).floor() / 100;
  }

  static QgPreflightResult run({
    required String body,
    List<String> recommendations = const <String>[],
    String disclaimer = '',
    bool patientFacing = true,
    int minWords = 40,
    int minRecommendations = 2,
    double maxGrade = 8,
  }) {
    final text = <String>[
      body,
      recommendations.join('\n'),
      disclaimer,
    ].where((s) => s.trim().isNotEmpty).join('\n');
    final lower = text.toLowerCase();
    final ws = words(body);
    final ss = sentences(text);
    final issues = <QgPreflightIssue>[];

    void add(String id, String label, String dimension, bool ok, String detail,
        String remedy) {
      issues.add(QgPreflightIssue(
        checkId: id, label: label, dimension: dimension,
        ok: ok, detail: detail, remedy: remedy,
      ));
    }

    // --- structure ---
    add('STR_BODY_SUBSTANCE', 'Body carries enough substance', 'structure',
        ws.length >= minWords, '${ws.length} words (min $minWords)',
        'Expand the clinical impression: what was measured, what it means, '
        'and what would change the interpretation.');

    final foundPlaceholders = placeholders
        .where((p) => lower.contains(p))
        .toList(growable: false);
    add('STR_NO_PLACEHOLDERS', 'No authoring placeholders', 'structure',
        foundPlaceholders.isEmpty,
        foundPlaceholders.isEmpty ? 'none' : foundPlaceholders.join(', '),
        'Replace every TODO/TBD/placeholder token with real content.');

    final trimmed = body.trim();
    final truncated = trimmed.isEmpty ||
        RegExp(r'(\.\.\.|…)$').hasMatch(trimmed) ||
        RegExp(r'\b(and|or|but|with|the|a|an|of|to|for|because|which|that|while|if)$',
                caseSensitive: false)
            .hasMatch(trimmed) ||
        !RegExp(r'''[.!?)\]"']$''').hasMatch(trimmed);
    add('STR_NO_TRUNCATION', 'Body terminates cleanly', 'structure', !truncated,
        truncated ? 'ends mid-thought or without terminal punctuation' : 'ok',
        'Complete the final sentence before signing.');

    final counts = <String, int>{};
    for (final s in ss) {
      final key = s
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (words(key).length < 6) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final dupes = counts.values.where((c) => c > 1).length;
    add('STR_NO_DUPLICATE_SENTENCES', 'No repeated boilerplate', 'structure',
        dupes == 0, '$dupes repeated sentence(s)',
        'Delete the duplicated sentence(s); repetition buries the signal.');

    // --- readability ---
    final grade = fkGrade(text);
    add('RDB_GRADE', 'Reading level within reach', 'readability',
        !patientFacing || grade <= maxGrade,
        'Flesch-Kincaid grade $grade (max $maxGrade)',
        'Shorten sentences and swap multi-syllable clinical words for plain ones.');

    var longSentences = 0;
    for (final s in ss) {
      if (words(s).length > 25) longSentences++;
    }
    add('RDB_SENTENCE_LENGTH', 'No wall-of-text sentences', 'readability',
        longSentences <= 1, '$longSentences sentence(s) over 25 words',
        'Split any sentence over 25 words into two.');

    if (patientFacing) {
      final unglossed = <String>[];
      jargonGlosses.forEach((term, gloss) {
        if (!lower.contains(term)) return;
        if (lower.contains(gloss)) return;
        unglossed.add(term);
      });
      unglossed.sort();
      add('RDB_JARGON_GLOSSED', 'Clinical terms glossed', 'readability',
          unglossed.isEmpty,
          unglossed.isEmpty ? 'all glossed' : unglossed.join(', '),
          'Add a plain-language gloss next to each flagged term.');
    }

    // --- actionability ---
    add('ACT_RECOMMENDATIONS', 'Concrete recommendations', 'actionability',
        recommendations.length >= minRecommendations,
        '${recommendations.length} recommendation(s) (min $minRecommendations)',
        'Add at least $minRecommendations specific next steps.');

    final hasTimeframe = RegExp(
      r'\b(?:within|in|after|every|next|by)\s+(?:the\s+)?(?:\d+|one|two|three|four|five|six|seven|ten|twelve|fourteen|twenty)\s*'
      r'(?:business\s+)?(?:hour|day|week|month|year)s?\b|\b(?:immediately|same\s+day|today|now|urgently)\b',
      caseSensitive: false,
    ).hasMatch('$lower ${recommendations.join(' ').toLowerCase()}');
    add('ACT_TIMEFRAME', 'Next step carries a deadline', 'actionability',
        hasTimeframe, hasTimeframe ? 'present' : 'absent',
        'Attach an explicit timeframe, e.g. "within 7 days". '
        'Advice without a deadline is not followed.');

    return QgPreflightResult(
      issues: issues,
      localGrade: grade,
      wordCount: ws.length,
      sentenceCount: ss.length,
    );
  }
}
