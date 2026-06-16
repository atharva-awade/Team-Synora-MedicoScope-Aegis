import 'package:medicoscope/services/api_service.dart';

/// Client for the Aegis governance APIs (Node /api/aegis/*): the clinician
/// case queue (RED actions the gate blocked), the verbs to resolve them, and
/// the tamper-evident audit ledger. Doctor/admin facing.
class AegisService {
  final ApiService _api;
  AegisService(String token) : _api = ApiService(token: token);

  /// Open clinician cases (RED actions awaiting human review).
  Future<List<Map<String, dynamic>>> getCases(
      {String status = 'AWAITING_REVIEW'}) async {
    try {
      final r = await _api.get('/aegis/cases?status=$status');
      return List<Map<String, dynamic>>.from(r['cases'] ?? const []);
    } catch (_) {
      return [];
    }
  }

  /// Full case detail + its ledger chain + integrity check.
  Future<Map<String, dynamic>?> getCase(String id) async {
    try {
      return await _api.get('/aegis/cases/$id');
    } catch (_) {
      return null;
    }
  }

  /// Resolve a case: verb in {approve, modify, override, escalate}.
  Future<Map<String, dynamic>?> resolve(String id, String verb,
      {String reason = '', Map<String, dynamic>? payload}) async {
    try {
      final body = <String, dynamic>{'reason': reason};
      if (payload != null) body['payload'] = payload;
      return await _api.post('/aegis/cases/$id/$verb', body);
    } catch (_) {
      return null;
    }
  }

  /// The tamper-evident decision ledger for a patient (+ integrity verdict).
  Future<Map<String, dynamic>?> getLedger(String patientId) async {
    try {
      return await _api.get('/aegis/ledger/$patientId');
    } catch (_) {
      return null;
    }
  }
}
