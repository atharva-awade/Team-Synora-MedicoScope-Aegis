import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:medicoscope/core/constants/api_constants.dart';

/// One event in the live agentic decision-trace, parsed from the backend's
/// Server-Sent-Events stream (POST /aegis/consult).
class ConsultEvent {
  final String event; // consult_start | triage_result | plan_published | tool_call | tool_result | diagnostic_result | plan_replan | guardrail_verdict | consult_complete | consult_error
  final Map<String, dynamic> data;
  const ConsultEvent(this.event, this.data);
}

/// Streams the autonomous consult from the chatbot's SSE endpoint. This is the
/// agent thinking out loud: triage -> plan -> tool calls -> fusion -> gate.
class ConsultService {
  /// Opens the SSE stream and yields each [ConsultEvent] as it arrives.
  /// Caller supplies the patient context + bearer token (required by the
  /// backend, which calls the auth-gated Node tool/aegis APIs).
  static Stream<ConsultEvent> run({
    required String patientId,
    required String patientName,
    String? doctorId,
    required String complaint,
    required String authToken,
    Map<String, dynamic> captures = const {},
  }) async* {
    final uri = Uri.parse('${ApiConstants.chatbotBaseUrl}/aegis/consult');
    final req = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode({
        'patient_id': patientId,
        'patient_name': patientName,
        'doctor_id': doctorId,
        'complaint': complaint,
        'auth_token': authToken,
        'captures': captures,
      });

    final client = http.Client();
    try {
      final resp = await client.send(req).timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) {
        yield ConsultEvent('consult_error',
            {'error': 'Consult failed (${resp.statusCode})'});
        return;
      }

      // SSE frames are separated by a blank line; each frame has an
      // "event:" line and a "data:" line.
      String? curEvent;
      final buf = StringBuffer();
      await for (final chunk in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.startsWith('event:')) {
          curEvent = chunk.substring(6).trim();
        } else if (chunk.startsWith('data:')) {
          buf.write(chunk.substring(5).trim());
        } else if (chunk.isEmpty) {
          // end of one frame
          if (curEvent != null && buf.isNotEmpty) {
            Map<String, dynamic> data = {};
            try {
              data = jsonDecode(buf.toString()) as Map<String, dynamic>;
            } catch (_) {}
            yield ConsultEvent(curEvent, data);
          }
          curEvent = null;
          buf.clear();
        }
      }
    } catch (e) {
      yield ConsultEvent('consult_error', {'error': e.toString()});
    } finally {
      client.close();
    }
  }
}
