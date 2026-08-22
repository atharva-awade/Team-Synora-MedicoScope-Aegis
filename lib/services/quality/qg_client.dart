import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:medicoscope/core/constants/api_constants.dart';

/// Thin client for the server-side Quality Gate.
///
/// There is exactly ONE implementation of the quality rules and it lives on the
/// server (`server/quality/`). That is a deliberate architectural decision, not
/// a shortcut. The previous design shipped a second copy of the rules inside the
/// app under a different version string, which meant the phone and the server
/// could disagree about the same report -- and the device belongs to the person
/// being audited. Two implementations of a quality rule are two definitions of
/// quality, so one of them was deleted.
///
/// What the app keeps is a fast local PRE-FLIGHT (see qg_preflight.dart) that is
/// labelled provisional, issues no certificate, and claims no authority.
class QgVerdict {
  final String status; // PASS | WARN | BLOCK
  final double score;
  final int scorePercent;
  final String certificateId;
  final String verdictDigest;
  final String contentDigest;
  final String packId;
  final String packVersion;
  final String packDigest;
  final String engineVersion;
  final String profile;
  final List<String> blocking;
  final List<Map<String, dynamic>> dimensions;
  final List<Map<String, dynamic>> checks;
  final List<Map<String, dynamic>> mustFix;
  final List<Map<String, dynamic>> claims;
  final Map<String, dynamic> metrics;
  final Map<String, dynamic> raw;

  const QgVerdict({
    required this.status,
    required this.score,
    required this.scorePercent,
    required this.certificateId,
    required this.verdictDigest,
    required this.contentDigest,
    required this.packId,
    required this.packVersion,
    required this.packDigest,
    required this.engineVersion,
    required this.profile,
    required this.blocking,
    required this.dimensions,
    required this.checks,
    required this.mustFix,
    required this.claims,
    required this.metrics,
    required this.raw,
  });

  bool get isPass => status == 'PASS';
  bool get isBlocked => status == 'BLOCK';
  bool get isWarning => status == 'WARN';

  double get groundingCoverage =>
      ((metrics['groundingCoverage'] as num?) ?? 1).toDouble();
  double get readingGrade => ((metrics['fkGrade'] as num?) ?? 0).toDouble();
  int get claimCount => ((metrics['claimCount'] as num?) ?? 0).toInt();
  int get boundClaimCount => ((metrics['boundClaimCount'] as num?) ?? 0).toInt();

  List<Map<String, dynamic>> get failedChecks =>
      checks.where((c) => c['ok'] != true).toList();

  static List<Map<String, dynamic>> _mapList(dynamic v) {
    if (v is! List) return const <Map<String, dynamic>>[];
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  factory QgVerdict.fromJson(Map<String, dynamic> j) => QgVerdict(
        status: (j['status'] ?? 'BLOCK').toString(),
        score: ((j['score'] as num?) ?? 0).toDouble(),
        scorePercent: ((j['scorePercent'] as num?) ??
                (((j['score'] as num?) ?? 0).toDouble() * 100).round())
            .toInt(),
        certificateId: (j['certificateId'] ?? '').toString(),
        verdictDigest: (j['verdictDigest'] ?? '').toString(),
        contentDigest: (j['contentDigest'] ?? '').toString(),
        packId: (j['packId'] ?? '').toString(),
        packVersion: (j['packVersion'] ?? '').toString(),
        packDigest: (j['packDigest'] ?? '').toString(),
        engineVersion: (j['engineVersion'] ?? '').toString(),
        profile: (j['profile'] ?? '').toString(),
        blocking: (j['blocking'] is List)
            ? List<String>.from((j['blocking'] as List).map((e) => e.toString()))
            : const <String>[],
        dimensions: _mapList(j['dimensions']),
        checks: _mapList(j['checks']),
        mustFix: _mapList(j['mustFix']),
        claims: _mapList(j['claims']),
        metrics: (j['metrics'] is Map)
            ? Map<String, dynamic>.from(j['metrics'] as Map)
            : const <String, dynamic>{},
        raw: j,
      );
}

/// Raised when the gate refuses to finalize. Carries the verdict so the UI can
/// show the reader exactly what to fix instead of a generic error.
class QgBlockedException implements Exception {
  final QgVerdict verdict;
  final String message;
  const QgBlockedException(this.verdict, this.message);
  @override
  String toString() => 'QgBlockedException: $message';
}

class QgClient {
  final String? token;
  final Duration timeout;

  const QgClient({this.token, this.timeout = const Duration(seconds: 20)});

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path) => Uri.parse('${ApiConstants.baseUrl}$path');

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final res = await http
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(timeout);
    final decoded = res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    // 409 is the gate refusing to finalize. It is a normal outcome, not a fault,
    // and it carries the remediation list the clinician needs.
    if (res.statusCode == 409 && decoded['verdict'] is Map) {
      throw QgBlockedException(
        QgVerdict.fromJson(Map<String, dynamic>.from(decoded['verdict'] as Map)),
        (decoded['message'] ?? 'Quality Gate blocked this content').toString(),
      );
    }
    throw Exception(
        'Quality Gate ${res.statusCode}: ${decoded['message'] ?? res.reasonPhrase}');
  }

  /// Pure evaluation. Cheap, no side effects, safe to call while typing.
  Future<QgVerdict> evaluate({
    required Map<String, dynamic> content,
    String profile = 'patient_report',
    String pack = 'medical',
    List<Map<String, dynamic>>? proposals,
  }) async {
    final res = await _post(ApiConstants.qualityGateEvaluate, <String, dynamic>{
      'content': content,
      'profile': profile,
      'pack': pack,
      if (proposals != null && proposals.isNotEmpty) 'proposals': proposals,
    });
    return QgVerdict.fromJson(Map<String, dynamic>.from(res['verdict'] as Map));
  }

  /// Evaluate and persist a certificate (idempotent on identical content).
  Future<Map<String, dynamic>> certify({
    required Map<String, dynamic> content,
    String profile = 'patient_report',
    String pack = 'medical',
    String? patientId,
    String? recordId,
  }) {
    return _post(ApiConstants.qualityGateCertify, <String, dynamic>{
      'content': content,
      'profile': profile,
      'pack': pack,
      if (patientId != null) 'patientId': patientId,
      if (recordId != null) 'recordId': recordId,
    });
  }

  /// The only sanctioned way to sign content. The server re-evaluates and will
  /// refuse a BLOCK unless a clinician supplies an override reason, which is
  /// then written into the append-only ledger.
  Future<Map<String, dynamic>> finalize({
    required Map<String, dynamic> content,
    String profile = 'patient_report',
    String pack = 'medical',
    String? patientId,
    String? recordId,
    String? overrideReason,
  }) {
    return _post(ApiConstants.qualityGateFinalize, <String, dynamic>{
      'content': content,
      'profile': profile,
      'pack': pack,
      if (patientId != null) 'patientId': patientId,
      if (recordId != null) 'recordId': recordId,
      if (overrideReason != null && overrideReason.trim().isNotEmpty)
        'override': <String, dynamic>{'reason': overrideReason.trim()},
    });
  }

  /// Ask whether a proposed rewrite is even allowed to be scored.
  Future<Map<String, dynamic>> checkRewrite({
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
    String profile = 'patient_report',
    String pack = 'medical',
  }) {
    return _post(ApiConstants.qualityGateRewriteCheck, <String, dynamic>{
      'before': before,
      'after': after,
      'profile': profile,
      'pack': pack,
    });
  }

  /// The published rule set. Useful for the in-app policy viewer -- a gate whose
  /// rules cannot be read is a gate nobody can argue with.
  Future<Map<String, dynamic>> packs() async {
    final res = await http
        .get(_uri(ApiConstants.qualityGatePacks), headers: _headers)
        .timeout(timeout);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Quality Gate packs ${res.statusCode}');
  }

  /// Public seal check. This is what the QR code on a printed report resolves
  /// to, and it needs no authentication because it discloses no clinical content.
  static Uri verifyUrlFor(String certificateId) =>
      Uri.parse('${ApiConstants.baseUrl}'
          '${ApiConstants.qualityGateVerify}/$certificateId');
}
