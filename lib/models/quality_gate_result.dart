import 'dart:convert';
import 'package:crypto/crypto.dart';

enum QualityGateStatus { passed, warning, blocked }

enum QualityPerspective { patient, clinician }

enum QualityDimensionType {
  structure,
  readability,
  safety,
  actionability,
  grounding,
}

class RedlineIssue {
  final String originalClause;
  final String suggestedReplacement;
  final String category; // 'jargon' | 'safety' | 'actionability' | 'structure'
  final String explanation;
  final bool isApplied;

  const RedlineIssue({
    required this.originalClause,
    required this.suggestedReplacement,
    required this.category,
    required this.explanation,
    this.isApplied = false,
  });

  RedlineIssue copyWith({bool? isApplied}) => RedlineIssue(
        originalClause: originalClause,
        suggestedReplacement: suggestedReplacement,
        category: category,
        explanation: explanation,
        isApplied: isApplied ?? this.isApplied,
      );

  Map<String, dynamic> toJson() => {
        'originalClause': originalClause,
        'suggestedReplacement': suggestedReplacement,
        'category': category,
        'explanation': explanation,
        'isApplied': isApplied,
      };

  factory RedlineIssue.fromJson(Map<String, dynamic> j) => RedlineIssue(
        originalClause: j['originalClause'] ?? '',
        suggestedReplacement: j['suggestedReplacement'] ?? '',
        category: j['category'] ?? 'jargon',
        explanation: j['explanation'] ?? '',
        isApplied: j['isApplied'] ?? false,
      );
}

class RepeatabilityProof {
  final int iterations;
  final double variance;
  final bool isDeterministic;
  final int matchedHashes;
  final double executionTimeMs;
  final String canonicalHash;

  const RepeatabilityProof({
    required this.iterations,
    required this.variance,
    required this.isDeterministic,
    required this.matchedHashes,
    required this.executionTimeMs,
    required this.canonicalHash,
  });

  Map<String, dynamic> toJson() => {
        'iterations': iterations,
        'variance': variance,
        'isDeterministic': isDeterministic,
        'matchedHashes': matchedHashes,
        'executionTimeMs': executionTimeMs,
        'canonicalHash': canonicalHash,
      };
}

class QualityDimensionScore {
  final QualityDimensionType type;
  final String title;
  final String description;
  final double score; // 0.0 to 1.0
  final QualityGateStatus status;
  final List<String> passedChecks;
  final List<String> warnings;
  final List<String> criticalIssues;

  const QualityDimensionScore({
    required this.type,
    required this.title,
    required this.description,
    required this.score,
    required this.status,
    this.passedChecks = const [],
    this.warnings = const [],
    this.criticalIssues = const [],
  });

  int get scorePercent => (score * 100).round();

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'title': title,
        'description': description,
        'score': score,
        'status': status.name,
        'passedChecks': passedChecks,
        'warnings': warnings,
        'criticalIssues': criticalIssues,
      };

  factory QualityDimensionScore.fromJson(Map<String, dynamic> j) =>
      QualityDimensionScore(
        type: QualityDimensionType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => QualityDimensionType.structure,
        ),
        title: j['title'] ?? '',
        description: j['description'] ?? '',
        score: (j['score'] as num?)?.toDouble() ?? 0.0,
        status: QualityGateStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => QualityGateStatus.warning,
        ),
        passedChecks: List<String>.from(j['passedChecks'] ?? []),
        warnings: List<String>.from(j['warnings'] ?? []),
        criticalIssues: List<String>.from(j['criticalIssues'] ?? []),
      );
}

/// The result of executing a Repeatable Quality Gate evaluation.
class QualityGateResult {
  final double overallScore; // 0.0 to 1.0
  final QualityGateStatus status;
  final QualityPerspective perspective;
  final String headline;
  final List<QualityDimensionScore> dimensions;
  final List<RedlineIssue> redlines;
  final List<String> autoFixSuggestions;
  final String? enhancedContent;
  final String auditHash;
  final String rulesVersion;
  final DateTime evaluatedAt;
  final String gateVersion;
  final String readingGradeLevel;
  final RepeatabilityProof? repeatabilityProof;

  // ── Server-issued certificate fields ────────────────────────────────────
  // Empty on a PROVISIONAL (local pre-flight) result and populated only when
  // the server engine has actually judged the content. `isProvisional` defaults
  // to true precisely so that a result nobody certified can never render as a
  // certification: the honest state is the default state.
  final String certificateId;
  final String verdictDigest;
  final String contentDigest;
  final String packRef;        // e.g. "medical@3.0.0#c0c39fcc"
  final String engineVersion;
  final String? verifyUrl;     // public seal-check URL (what the QR encodes)
  final bool isProvisional;
  final List<String> blockingCheckIds;
  final double groundingCoverage;
  final int claimCount;
  final int boundClaimCount;
  final bool finalized;
  final String? overrideReason;

  const QualityGateResult({
    required this.overallScore,
    required this.status,
    this.perspective = QualityPerspective.clinician,
    required this.headline,
    required this.dimensions,
    this.redlines = const [],
    this.autoFixSuggestions = const [],
    this.enhancedContent,
    required this.auditHash,
    required this.rulesVersion,
    required this.evaluatedAt,
    this.gateVersion = 'Aegis-QGate-v2.6.0',
    this.readingGradeLevel = 'Grade 7.4 (Patient Accessible)',
    this.repeatabilityProof,
    this.certificateId = '',
    this.verdictDigest = '',
    this.contentDigest = '',
    this.packRef = '',
    this.engineVersion = '',
    this.verifyUrl,
    this.isProvisional = true,
    this.blockingCheckIds = const [],
    this.groundingCoverage = 1.0,
    this.claimCount = 0,
    this.boundClaimCount = 0,
    this.finalized = false,
    this.overrideReason,
  });

  /// True only when a server-issued certificate backs this result.
  bool get isCertified => !isProvisional && certificateId.isNotEmpty;

  /// One line safe to print on a report footer or read aloud on stage.
  String get sealLine => isCertified
      ? 'AEGIS QUALITY GATE  |  $statusLabel  |  $overallScorePercent%  |  '
          'cert $certificateId  |  $packRef  |  engine $engineVersion'
      : 'PROVISIONAL PRE-FLIGHT  |  not certified  |  no certificate issued';

  String get statusLabel {
    switch (status) {
      case QualityGateStatus.passed:
        return 'PASS';
      case QualityGateStatus.warning:
        return 'WARN';
      case QualityGateStatus.blocked:
        return 'BLOCK';
    }
  }

  int get overallScorePercent => (overallScore * 100).round();
  bool get isPassed => status == QualityGateStatus.passed;
  bool get isBlocked => status == QualityGateStatus.blocked;
  bool get hasWarnings => status == QualityGateStatus.warning;

  QualityGateResult copyWith({
    RepeatabilityProof? repeatabilityProof,
    List<RedlineIssue>? redlines,
    double? overallScore,
    QualityGateStatus? status,
    QualityPerspective? perspective,
    bool? finalized,
    String? overrideReason,
  }) {
    return QualityGateResult(
      overallScore: overallScore ?? this.overallScore,
      status: status ?? this.status,
      perspective: perspective ?? this.perspective,
      headline: headline,
      dimensions: dimensions,
      redlines: redlines ?? this.redlines,
      autoFixSuggestions: autoFixSuggestions,
      enhancedContent: enhancedContent,
      auditHash: auditHash,
      rulesVersion: rulesVersion,
      evaluatedAt: evaluatedAt,
      gateVersion: gateVersion,
      readingGradeLevel: readingGradeLevel,
      repeatabilityProof: repeatabilityProof ?? this.repeatabilityProof,
      certificateId: certificateId,
      verdictDigest: verdictDigest,
      contentDigest: contentDigest,
      packRef: packRef,
      engineVersion: engineVersion,
      verifyUrl: verifyUrl,
      isProvisional: isProvisional,
      blockingCheckIds: blockingCheckIds,
      groundingCoverage: groundingCoverage,
      claimCount: claimCount,
      boundClaimCount: boundClaimCount,
      finalized: finalized ?? this.finalized,
      overrideReason: overrideReason ?? this.overrideReason,
    );
  }

  /// A locally computed digest over the raw text. Retained for backward
  /// compatibility only.
  ///
  /// It is NOT a certificate and must never be displayed as one. A hash computed
  /// on the device says nothing about whether the content passed a gate -- the
  /// device is controlled by the person being audited, and this function does
  /// not look at the rules, the evidence, or the verdict. The real, reproducible
  /// identity is `certificateId`, derived server-side from
  /// (contentDigest, packDigest, engineVersion).
  @Deprecated('Use the server-issued certificateId. This is a text digest, not a certificate.')
  static String generateAuditHash({
    required String rawContent,
    required double score,
    required String rulesVersion,
    DateTime? timestamp,
  }) {
    final payload = '${rawContent.trim()}|${score.toStringAsFixed(4)}|$rulesVersion';
    return sha256.convert(utf8.encode(payload)).toString().substring(0, 16).toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'overallScore': overallScore,
        'status': status.name,
        'perspective': perspective.name,
        'headline': headline,
        'dimensions': dimensions.map((d) => d.toJson()).toList(),
        'redlines': redlines.map((r) => r.toJson()).toList(),
        'autoFixSuggestions': autoFixSuggestions,
        'enhancedContent': enhancedContent,
        'auditHash': auditHash,
        'rulesVersion': rulesVersion,
        'evaluatedAt': evaluatedAt.toIso8601String(),
        'gateVersion': gateVersion,
        'readingGradeLevel': readingGradeLevel,
        'repeatabilityProof': repeatabilityProof?.toJson(),
        'certificateId': certificateId,
        'verdictDigest': verdictDigest,
        'contentDigest': contentDigest,
        'packRef': packRef,
        'engineVersion': engineVersion,
        'verifyUrl': verifyUrl,
        'isProvisional': isProvisional,
        'blockingCheckIds': blockingCheckIds,
        'groundingCoverage': groundingCoverage,
        'claimCount': claimCount,
        'boundClaimCount': boundClaimCount,
        'finalized': finalized,
        'overrideReason': overrideReason,
      };

  factory QualityGateResult.fromJson(Map<String, dynamic> j) =>
      QualityGateResult(
        overallScore: (j['overallScore'] as num?)?.toDouble() ?? 0.0,
        status: QualityGateStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => QualityGateStatus.blocked,
        ),
        perspective: QualityPerspective.values.firstWhere(
          (e) => e.name == j['perspective'],
          orElse: () => QualityPerspective.clinician,
        ),
        headline: j['headline'] ?? '',
        dimensions: (j['dimensions'] as List? ?? [])
            .map((e) => QualityDimensionScore.fromJson(e as Map<String, dynamic>))
            .toList(),
        redlines: (j['redlines'] as List? ?? [])
            .map((e) => RedlineIssue.fromJson(e as Map<String, dynamic>))
            .toList(),
        autoFixSuggestions: List<String>.from(j['autoFixSuggestions'] ?? []),
        enhancedContent: j['enhancedContent'],
        auditHash: j['auditHash'] ?? '',
        rulesVersion: j['rulesVersion'] ?? 'QG-2026.1',
        evaluatedAt: DateTime.tryParse(j['evaluatedAt'] ?? '') ?? DateTime.now(),
        gateVersion: j['gateVersion'] ?? 'Aegis-QGate-v2.6.0',
        readingGradeLevel: j['readingGradeLevel'] ?? 'Grade 7.4 (Patient Accessible)',
        certificateId: j['certificateId'] ?? '',
        verdictDigest: j['verdictDigest'] ?? '',
        contentDigest: j['contentDigest'] ?? '',
        packRef: j['packRef'] ?? '',
        engineVersion: j['engineVersion'] ?? '',
        verifyUrl: j['verifyUrl'],
        isProvisional: j['isProvisional'] ?? true,
        blockingCheckIds: List<String>.from(j['blockingCheckIds'] ?? const []),
        groundingCoverage: (j['groundingCoverage'] as num?)?.toDouble() ?? 1.0,
        claimCount: (j['claimCount'] as num?)?.toInt() ?? 0,
        boundClaimCount: (j['boundClaimCount'] as num?)?.toInt() ?? 0,
        finalized: j['finalized'] ?? false,
        overrideReason: j['overrideReason'],
      );
}
