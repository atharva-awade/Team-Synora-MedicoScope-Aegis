import 'package:shared_preferences/shared_preferences.dart';

import 'package:medicoscope/core/constants/api_constants.dart';
import 'package:medicoscope/models/detection_record.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/models/quality_gate_result.dart';
import 'package:medicoscope/services/quality/qg_client.dart';
import 'package:medicoscope/services/quality/qg_content.dart';
import 'package:medicoscope/services/quality/qg_preflight.dart';

// Re-exported deliberately: callers of this service handle QgBlockedException
// (the gate refusing to finalize) and read QgVerdict fields, and they should not
// have to reach past this facade to do it. Narrowing this export breaks
// report_detail_screen.dart.
export 'package:medicoscope/services/quality/qg_client.dart'
    show QgVerdict, QgBlockedException;

/// Aegis Repeatable Quality Gate -- app-side adapter.
///
/// WHAT CHANGED AND WHY IT MATTERS
///
/// The previous version of this file scored reports locally, and several of its
/// dimension scores were literal constants (`score: 0.98`, `0.96`, `0.97`). A
/// gate that cannot return a low number is not a gate, it is a badge. It also
/// kept its own rule set under a different version string from the server's, so
/// the phone and the backend could disagree about the same report, and it
/// derived an "audit seal" from a device-side hash that no third party could
/// reproduce or check.
///
/// The rules now live in exactly one place -- `server/quality/packs/*.json`,
/// executed by `server/quality/lib/engine.js` -- and this file does two jobs:
///
///   PRE-FLIGHT   A synchronous, offline, explicitly PROVISIONAL checklist so a
///                clinician sees problems while typing. It issues no
///                certificate, computes no hash, and implements only checks that
///                need nothing but the text, so it can never imply a report is
///                safe when the gate would block it.
///
///   CERTIFY      The authoritative path. The server re-derives the verdict from
///                the content it is given, so the app cannot talk it into
///                signing something that fails. What comes back is a
///                reproducible certificate id: a pure function of
///                (content digest, policy pack digest, engine version), with the
///                timestamp deliberately OUTSIDE the hash so the seal can be
///                recomputed by anyone, forever.
class QualityGateService {
  /// Kept for display compatibility. The authoritative version is the packRef
  /// on each verdict, e.g. "medical@3.0.0#c0c39fcc".
  static const String currentRulesVersion = 'QG-ENGINE-3 (server-authoritative)';

  static const String _tokenKey = 'auth_token';

  static Future<String?> _token() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (_) {
      return null;
    }
  }

  static Future<QgClient> _client() async => QgClient(token: await _token());

  static String _profileFor(QualityPerspective p) =>
      p == QualityPerspective.patient ? 'patient_report' : 'clinician_report';

  // ══════════════════════════════════════════════════════════════════════
  // PRE-FLIGHT (synchronous, provisional, never a certification)
  // ══════════════════════════════════════════════════════════════════════

  /// Provisional local check of a detection record + physician notes.
  ///
  /// Synchronous so existing UI call sites keep working, and marked
  /// `isProvisional` so no caller can accidentally present it as certified.
  static QualityGateResult auditDetectionRecord({
    required DetectionRecord record,
    required String patientName,
    String? doctorNotes,
    QualityPerspective perspective = QualityPerspective.clinician,
  }) {
    final content = QgContent.fromDetectionRecord(
      record,
      doctorNotes: doctorNotes,
      patientName: patientName,
    );
    final patientFacing = perspective == QualityPerspective.patient;
    final pre = QgPreflight.run(
      body: (content['body'] ?? '').toString(),
      recommendations: const <String>[],
      disclaimer: (content['disclaimer'] ?? '').toString(),
      patientFacing: patientFacing,
      minWords: patientFacing ? 40 : 25,
      minRecommendations: 0,
      maxGrade: patientFacing ? 8 : 14,
    );
    return _fromPreflight(
      pre,
      perspective: perspective,
      notesForRedlines: doctorNotes,
    );
  }

  /// Provisional local check of a screening result.
  static QualityGateResult auditScreeningResult(
    DiseaseRiskResult result, {
    QualityPerspective perspective = QualityPerspective.patient,
  }) {
    final content = QgContent.fromScreeningResult(result);
    final patientFacing = perspective == QualityPerspective.patient;
    final pre = QgPreflight.run(
      body: (content['body'] ?? '').toString(),
      recommendations: result.recommendations,
      disclaimer: (content['disclaimer'] ?? '').toString(),
      patientFacing: patientFacing,
      minWords: patientFacing ? 40 : 25,
      minRecommendations: 2,
      maxGrade: patientFacing ? 8 : 14,
    );
    return _fromPreflight(
      pre,
      perspective: perspective,
      notesForRedlines: result.headline,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // CERTIFY / FINALIZE (authoritative, server-side)
  // ══════════════════════════════════════════════════════════════════════

  /// Ask the server engine to judge a screening result and issue a certificate.
  static Future<QualityGateResult> certifyScreeningResult(
    DiseaseRiskResult result, {
    QualityPerspective perspective = QualityPerspective.patient,
    String? patientId,
  }) async {
    final client = await _client();
    final content = QgContent.fromScreeningResult(result);
    final res = await client.certify(
      content: content,
      profile: _profileFor(perspective),
      patientId: patientId,
    );
    final verdict =
        QgVerdict.fromJson(Map<String, dynamic>.from(res['verdict'] as Map));
    final cert = res['certificate'] is Map
        ? Map<String, dynamic>.from(res['certificate'] as Map)
        : const <String, dynamic>{};
    return _fromVerdict(verdict,
        perspective: perspective,
        verifyUrl: cert['verifyUrl']?.toString(),
        finalized: cert['finalized'] == true,
        subjectTitle: result.headline);
  }

  /// Judge a physician-signed report. Does not finalize.
  static Future<QualityGateResult> certifyDetectionRecord({
    required DetectionRecord record,
    required String patientName,
    String? doctorNotes,
    QualityPerspective perspective = QualityPerspective.clinician,
  }) async {
    final client = await _client();
    final content = QgContent.fromDetectionRecord(record,
        doctorNotes: doctorNotes, patientName: patientName);
    final res = await client.certify(
      content: content,
      profile: _profileFor(perspective),
      patientId: record.patientId,
      recordId: record.id,
    );
    final verdict =
        QgVerdict.fromJson(Map<String, dynamic>.from(res['verdict'] as Map));
    final cert = res['certificate'] is Map
        ? Map<String, dynamic>.from(res['certificate'] as Map)
        : const <String, dynamic>{};
    return _fromVerdict(verdict,
        perspective: perspective,
        verifyUrl: cert['verifyUrl']?.toString(),
        finalized: cert['finalized'] == true,
        subjectTitle: record.className,
        notesForRedlines: doctorNotes);
  }

  /// The ONLY sanctioned way to sign a report.
  ///
  /// The server re-evaluates the content and refuses on BLOCK. Pass
  /// [overrideReason] to finalize anyway -- permitted for a doctor or admin
  /// only, and written into the append-only ledger with their identity attached.
  /// Throws [QgBlockedException] when the gate refuses; the exception carries the
  /// verdict so the caller can show exactly what has to change.
  static Future<QualityGateResult> finalizeDetectionRecord({
    required DetectionRecord record,
    required String patientName,
    String? doctorNotes,
    QualityPerspective perspective = QualityPerspective.clinician,
    String? overrideReason,
  }) async {
    final client = await _client();
    final content = QgContent.fromDetectionRecord(record,
        doctorNotes: doctorNotes, patientName: patientName);
    final res = await client.finalize(
      content: content,
      profile: _profileFor(perspective),
      patientId: record.patientId,
      recordId: record.id,
      overrideReason: overrideReason,
    );
    final verdict =
        QgVerdict.fromJson(Map<String, dynamic>.from(res['verdict'] as Map));
    final cert = res['certificate'] is Map
        ? Map<String, dynamic>.from(res['certificate'] as Map)
        : const <String, dynamic>{};
    return _fromVerdict(verdict,
        perspective: perspective,
        verifyUrl: cert['verifyUrl']?.toString(),
        finalized: true,
        overrideReason: cert['overrideReason']?.toString(),
        subjectTitle: record.className,
        notesForRedlines: doctorNotes);
  }

  /// Ask whether a proposed rewrite is even allowed to be scored.
  ///
  /// The contract freezes measurements, risk level, cited evidence and negation
  /// polarity. Prose is free; facts are not. A rewrite that changes a number is
  /// rejected BEFORE it is scored, which is what makes it safe to let a model
  /// repair its own output.
  static Future<Map<String, dynamic>> checkRewrite({
    required DetectionRecord record,
    required String patientName,
    required String notesBefore,
    required String notesAfter,
    QualityPerspective perspective = QualityPerspective.clinician,
  }) async {
    final client = await _client();
    return client.checkRewrite(
      before: QgContent.fromDetectionRecord(record,
          doctorNotes: notesBefore, patientName: patientName),
      after: QgContent.fromDetectionRecord(record,
          doctorNotes: notesAfter, patientName: patientName),
      profile: _profileFor(perspective),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // REPEATABILITY PROOF
  // ══════════════════════════════════════════════════════════════════════

  /// Prove repeatability the only way that means anything: submit the identical
  /// content [iterations] times as separate HTTP requests and check that every
  /// response carries the same certificate id and the same score.
  ///
  /// The previous implementation looped a local pure function and reported that
  /// it agreed with itself, which is true of any function and proves nothing.
  /// This crosses a process boundary, a network, and a JSON round trip, so a
  /// match is evidence that the verdict is a function of the content rather than
  /// of the moment it was asked.
  static Future<RepeatabilityProof> runRepeatabilityBenchmark({
    required DetectionRecord record,
    required String patientName,
    String? doctorNotes,
    int iterations = 10,
    QualityPerspective perspective = QualityPerspective.clinician,
  }) async {
    final sw = Stopwatch()..start();
    final client = await _client();
    final content = QgContent.fromDetectionRecord(record,
        doctorNotes: doctorNotes, patientName: patientName);
    final profile = _profileFor(perspective);

    final scores = <double>[];
    final certificates = <String>[];
    for (var i = 0; i < iterations; i++) {
      final v = await client.evaluate(content: content, profile: profile);
      scores.add(v.score);
      certificates.add(v.certificateId);
    }
    sw.stop();

    final canonical = certificates.isEmpty ? '' : certificates.first;
    final matched = certificates.where((c) => c == canonical).length;

    // Exact equality, not "variance under an epsilon": summing identical
    // doubles can itself introduce rounding, so a small variance would be
    // measuring this method's arithmetic instead of the gate's behaviour.
    final distinctScores = scores.toSet().length;
    double variance = 0;
    if (distinctScores > 1) {
      final mean = scores.reduce((a, b) => a + b) / scores.length;
      var acc = 0.0;
      for (final s in scores) {
        acc += (s - mean) * (s - mean);
      }
      variance = acc / scores.length;
    }

    return RepeatabilityProof(
      iterations: iterations,
      variance: variance,
      isDeterministic:
          distinctScores <= 1 && matched == iterations && iterations > 0,
      matchedHashes: matched,
      executionTimeMs: sw.elapsedMicroseconds / 1000.0,
      canonicalHash: canonical,
    );
  }

  /// The published rule set, for the in-app policy viewer.
  static Future<Map<String, dynamic>> fetchPolicyPacks() async {
    final client = await _client();
    return client.packs();
  }

  static Uri verifyUrlFor(String certificateId) =>
      QgClient.verifyUrlFor(certificateId);

  // ══════════════════════════════════════════════════════════════════════
  // mapping
  // ══════════════════════════════════════════════════════════════════════

  static QualityGateStatus _statusOf(String s) {
    switch (s) {
      case 'PASS':
        return QualityGateStatus.passed;
      case 'WARN':
        return QualityGateStatus.warning;
      default:
        return QualityGateStatus.blocked;
    }
  }

  static QualityDimensionType _dimTypeOf(String id) {
    switch (id) {
      case 'readability':
        return QualityDimensionType.readability;
      case 'safety':
        return QualityDimensionType.safety;
      case 'actionability':
        return QualityDimensionType.actionability;
      case 'grounding':
        return QualityDimensionType.grounding;
      default:
        return QualityDimensionType.structure;
    }
  }

  static String _gradeLabel(double grade) {
    final band = grade < 6
        ? 'Very accessible'
        : grade < 9
            ? 'Patient accessible'
            : grade < 12
                ? 'Demanding'
                : 'Specialist';
    return 'Grade ${grade.toStringAsFixed(1)} ($band)';
  }

  /// Turn the local pre-flight into the shared result type, clearly provisional.
  static QualityGateResult _fromPreflight(
    QgPreflightResult pre, {
    required QualityPerspective perspective,
    String? notesForRedlines,
  }) {
    final byDim = <String, List<QgPreflightIssue>>{};
    for (final i in pre.issues) {
      byDim.putIfAbsent(i.dimension, () => <QgPreflightIssue>[]).add(i);
    }

    // Dimensions the pre-flight cannot see -- safety and grounding, the two that
    // actually gate a report -- are OMITTED rather than given a made-up score.
    // A green bar for a check that never ran is the exact failure mode this
    // rewrite exists to remove.
    final dims = <QualityDimensionScore>[];
    const orderedDims = <String>[
      'structure', 'readability', 'safety', 'actionability', 'grounding',
    ];
    for (final id in orderedDims) {
      final own = byDim[id] ?? const <QgPreflightIssue>[];
      if (own.isEmpty) continue;
      final passed = own.where((i) => i.ok).map((i) => i.label).toList();
      final failed = own.where((i) => !i.ok).toList();
      final score = passed.length / own.length;
      dims.add(QualityDimensionScore(
        type: _dimTypeOf(id),
        title: '${_dimTitle(id)} (pre-flight)',
        description:
            'Local pre-flight only: ${passed.length} of ${own.length} text-only '
            'checks pass. Safety and evidence grounding are not evaluated offline.',
        score: score,
        status: score >= 0.999
            ? QualityGateStatus.passed
            : score >= 0.6
                ? QualityGateStatus.warning
                : QualityGateStatus.blocked,
        passedChecks: passed,
        warnings: failed.map((i) => '${i.label}: ${i.detail}').toList(),
      ));
    }

    final redlines = <RedlineIssue>[
      ..._jargonRedlines(notesForRedlines ?? ''),
      ...pre.failures.map((f) => RedlineIssue(
            originalClause: f.label,
            suggestedReplacement: f.remedy,
            category: f.dimension,
            explanation: '${f.detail} — provisional local check, '
                'not part of any certificate.',
          )),
    ];

    return QualityGateResult(
      overallScore: pre.localPassRatio,
      // Always `warning`: a pre-flight has no authority to pass anything, and
      // rendering it as passed is how a badge starts lying.
      status: QualityGateStatus.warning,
      perspective: perspective,
      headline: 'PROVISIONAL — ${pre.passedCount}/${pre.totalCount} local '
          'pre-flight checks pass. Not certified: run the Quality Gate to get a '
          'verdict and a certificate.',
      dimensions: dims,
      redlines: redlines,
      autoFixSuggestions:
          pre.failures.map((f) => f.remedy).toList(growable: false),
      enhancedContent: null,
      auditHash: '—',
      rulesVersion: '$currentRulesVersion (pre-flight subset)',
      evaluatedAt: DateTime.now(),
      readingGradeLevel: _gradeLabel(pre.localGrade),
      isProvisional: true,
    );
  }

  /// Turn a server verdict into the shared result type.
  static QualityGateResult _fromVerdict(
    QgVerdict v, {
    required QualityPerspective perspective,
    required String subjectTitle,
    String? verifyUrl,
    bool finalized = false,
    String? overrideReason,
    String? notesForRedlines,
  }) {
    final dims = <QualityDimensionScore>[];
    for (final d in v.dimensions) {
      final id = (d['id'] ?? '').toString();
      final own = v.checks.where((c) => c['dimension'] == id).toList();
      final passed = own
          .where((c) => c['ok'] == true)
          .map((c) => (c['message'] ?? c['id']).toString())
          .toList();
      final failedMinor = own
          .where((c) => c['ok'] != true && c['severity'] != 'critical')
          .map((c) => '${c['message']}: ${c['detail']}')
          .toList();
      final failedCritical = own
          .where((c) => c['ok'] != true && c['severity'] == 'critical')
          .map((c) => '${c['message']}: ${c['detail']}')
          .toList();
      final score = ((d['score'] as num?) ?? 0).toDouble();
      dims.add(QualityDimensionScore(
        type: _dimTypeOf(id),
        title: (d['title'] ?? _dimTitle(id)).toString(),
        description: _dimTitle(id),
        score: score,
        status: failedCritical.isNotEmpty
            ? QualityGateStatus.blocked
            : score >= 0.85
                ? QualityGateStatus.passed
                : QualityGateStatus.warning,
        passedChecks: passed,
        warnings: failedMinor,
        criticalIssues: failedCritical,
      ));
    }

    final redlines = <RedlineIssue>[
      ..._jargonRedlines(notesForRedlines ?? ''),
      ...v.mustFix.map((m) => RedlineIssue(
            originalClause: (m['message'] ?? m['id']).toString(),
            suggestedReplacement: (m['remedy'] ?? '').toString(),
            category: (m['severity'] ?? 'major').toString(),
            explanation: (m['detail'] ?? '').toString(),
          )),
    ];

    final status = _statusOf(v.status);
    final headline = status == QualityGateStatus.passed
        ? 'PASS — certified ${v.scorePercent}% · certificate ${v.certificateId}'
        : status == QualityGateStatus.warning
            ? 'PASS WITH REMARKS — ${v.scorePercent}% · '
                '${v.failedChecks.length} check(s) need attention'
            : 'BLOCKED — ${v.blocking.length} critical check(s) must be fixed '
                'before this can be signed';

    return QualityGateResult(
      overallScore: v.score,
      status: status,
      perspective: perspective,
      headline: headline,
      dimensions: dims,
      redlines: redlines,
      autoFixSuggestions: v.mustFix
          .map((m) => (m['remedy'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList(growable: false),
      enhancedContent: _certifiedBlock(v, subjectTitle, verifyUrl),
      auditHash: v.certificateId.isEmpty ? '—' : v.certificateId,
      rulesVersion: '${v.packId}@${v.packVersion} · engine ${v.engineVersion}',
      evaluatedAt: DateTime.now(),
      readingGradeLevel: _gradeLabel(v.readingGrade),
      certificateId: v.certificateId,
      verdictDigest: v.verdictDigest,
      contentDigest: v.contentDigest,
      packRef: '${v.packId}@${v.packVersion}#${_short(v.packDigest)}',
      engineVersion: v.engineVersion,
      verifyUrl: verifyUrl ??
          (v.certificateId.isEmpty
              ? null
              : QgClient.verifyUrlFor(v.certificateId).toString()),
      isProvisional: false,
      blockingCheckIds: v.blocking,
      groundingCoverage: v.groundingCoverage,
      claimCount: v.claimCount,
      boundClaimCount: v.boundClaimCount,
      finalized: finalized,
      overrideReason: overrideReason,
    );
  }

  static String _short(String digest, [int n = 8]) =>
      digest.length <= n ? digest : digest.substring(0, n);

  static String _dimTitle(String id) {
    switch (id) {
      case 'structure':
        return 'Structure & Completeness';
      case 'readability':
        return 'Readability & Accessibility';
      case 'safety':
        return 'Clinical Safety & Scope';
      case 'actionability':
        return 'Actionability';
      case 'grounding':
        return 'Evidence Grounding';
      default:
        return id;
    }
  }

  static List<RedlineIssue> _jargonRedlines(String text) {
    if (text.trim().isEmpty) return const <RedlineIssue>[];
    final lower = text.toLowerCase();
    final out = <RedlineIssue>[];
    QgPreflight.jargonGlosses.forEach((term, gloss) {
      if (!lower.contains(term)) return;
      if (lower.contains(gloss)) return;
      out.add(RedlineIssue(
        originalClause: term,
        suggestedReplacement: '$gloss ($term)',
        category: 'jargon',
        explanation: 'Clinical term with no plain-language gloss nearby. '
            'The reader has to already know the word to understand the sentence.',
      ));
    });
    return out;
  }

  static String _certifiedBlock(QgVerdict v, String title, String? verifyUrl) {
    final sb = StringBuffer();
    sb.writeln('=== AEGIS QUALITY GATE CERTIFICATE ===');
    sb.writeln('Subject            : $title');
    sb.writeln('Verdict            : ${v.status} (${v.scorePercent}%)');
    sb.writeln('Certificate        : ${v.certificateId}');
    sb.writeln('Content digest     : ${v.contentDigest}');
    sb.writeln('Verdict digest     : ${v.verdictDigest}');
    sb.writeln('Judged by          : ${v.packId}@${v.packVersion} '
        '(pack ${v.packDigest}), engine ${v.engineVersion}');
    sb.writeln('Profile            : ${v.profile}');
    sb.writeln('Evidence grounding : ${v.boundClaimCount}/${v.claimCount} '
        'numeric claims bound to evidence '
        '(${(v.groundingCoverage * 100).toStringAsFixed(0)}%)');
    sb.writeln('Reading level      : Flesch-Kincaid grade ${v.readingGrade}');
    if (v.blocking.isNotEmpty) {
      sb.writeln('Blocking checks    : ${v.blocking.join(', ')}');
    }
    if (verifyUrl != null && verifyUrl.isNotEmpty) {
      sb.writeln('Verify             : $verifyUrl');
    }
    sb.writeln('');
    sb.writeln('The certificate id above is a pure function of the content '
        'digest, the policy pack digest and the engine version. The timestamp is '
        'deliberately NOT part of it, so anyone holding this content and this '
        'pack can recompute the same id and confirm the verdict independently.');
    sb.writeln('Endpoint: ${ApiConstants.baseUrl}${ApiConstants.qualityGateVerify}/${v.certificateId}');
    return sb.toString();
  }
}
