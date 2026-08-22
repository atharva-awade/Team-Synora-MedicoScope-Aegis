import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/detection_record.dart';
import 'package:medicoscope/models/disease_risk_result.dart';

/// Builds the canonical "gate content" payload the Quality Gate evaluates.
///
/// This is the seam between the app's domain models and the gate. The gate does
/// not know what a DiseaseRiskResult is, and it must not: it takes prose plus a
/// set of evidence envelopes and asks whether the prose is supported by the
/// evidence. Keeping that translation in one small file is what lets the same
/// engine certify a lab report, a consult summary, or something that has not
/// been built yet.
///
/// The important work here is EVIDENCE CONSTRUCTION. Every MarkerFinding the
/// analysers produced becomes an evidence fact with a value, a unit and a
/// fidelity tier, so the server can check that each number appearing in the
/// narrative actually traces back to a measurement. Get this mapping wrong and
/// the grounding check has nothing to bind against.
class QgContent {
  /// Fidelity tiers mirror `server/aegis/envelopes.js`. They are not cosmetic:
  /// a value from a hand-tuned formula is capped and must be hedged in prose,
  /// while a parsed lab value may be stated plainly.
  static String fidelityForMethod(DetectionMethod m) {
    switch (m) {
      case DetectionMethod.labReportPdf:
        return 'real';
      case DetectionMethod.retinalFundus:
        return 'real';
      case DetectionMethod.vitalsWearable:
        return 'partial';
      case DetectionMethod.symptomQuestionnaire:
        return 'partial';
      case DetectionMethod.ppgBloodPressure:
        return 'heuristic';
      case DetectionMethod.conjunctivalPallor:
        return 'heuristic';
      case DetectionMethod.respiratoryAcoustic:
        return 'fabricated_scale';
    }
  }

  static String fidelityForCategory(String category) {
    switch (category) {
      case 'skin':
      case 'chest':
      case 'brain':
      case 'heart_sound':
        return 'real';
      case 'questionnaire':
        return 'partial';
      default:
        return 'heuristic';
    }
  }

  /// Pull the leading number out of a MarkerFinding's string value.
  /// Returns null when there is no number, which is correct: a qualitative
  /// finding is not something a numeric claim can bind to.
  static num? parseValue(String raw) {
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
    if (m == null) return null;
    return num.tryParse(m.group(0)!);
  }

  /// Screening result -> gate content, with one evidence envelope per modality.
  static Map<String, dynamic> fromScreeningResult(
    DiseaseRiskResult result, {
    String? llmExplanationOverride,
  }) {
    final findings = <Map<String, dynamic>>[];
    for (final f in result.findings) {
      final v = parseValue(f.value);
      if (v == null) continue;
      findings.add(<String, dynamic>{
        'label': f.name,
        'value': v,
        'unit': f.unit.isEmpty ? null : f.unit,
      });
    }

    final evidence = <Map<String, dynamic>>[
      <String, dynamic>{
        'toolId': '${result.disease.name}_${result.method.name}',
        'modality': result.method.name,
        'fidelity': fidelityForMethod(result.method),
        'label': 'risk_score',
        'value': result.score,
        'unit': 'ratio',
        'provenance': <String, dynamic>{'source': result.dataSource},
        'findings': findings,
      },
    ];

    final bodyParts = <String>[
      result.headline,
      if ((llmExplanationOverride ?? result.llmExplanation ?? '').trim().isNotEmpty)
        (llmExplanationOverride ?? result.llmExplanation!).trim(),
      // Marker interpretations are part of the narrative the reader acts on, so
      // they are part of what gets checked -- not hidden from the gate.
      ...result.findings
          .where((f) => f.interpretation.trim().isNotEmpty)
          .map((f) => '${f.name}: ${f.value} ${f.unit} '
              '(reference range ${f.referenceRange}). ${f.interpretation}')
          .toList(),
      if (result.topContributors.isNotEmpty)
        'Main contributors: ${result.topContributors.join(', ')}.',
      'This is a screening signal and not a diagnosis. '
          'It requires clinical confirmation.',
    ];

    return <String, dynamic>{
      'kind': 'screening_report',
      'title': result.headline,
      'category': result.disease.name,
      'riskLevel': result.risk.label.toLowerCase(),
      'score': result.score,
      'confidence': result.score,
      'body': bodyParts.join('\n'),
      'recommendations': result.recommendations,
      'disclaimer': 'Screening-grade result from ${result.dataSource}. '
          'Requires clinical confirmation and is not a diagnosis.',
      'evidence': evidence,
      'locale': 'en',
    };
  }

  /// Detection record + physician notes -> gate content for the sign-off path.
  static Map<String, dynamic> fromDetectionRecord(
    DetectionRecord record, {
    String? doctorNotes,
    String? patientName,
  }) {
    final evidence = <Map<String, dynamic>>[
      <String, dynamic>{
        'toolId': '${record.category}_classifier',
        'modality': record.category,
        'fidelity': fidelityForCategory(record.category),
        'label': 'model_confidence',
        'value': record.confidence,
        'unit': 'ratio',
        'provenance': <String, dynamic>{
          'model': '${record.category}_model.tflite',
          'source': record.performedByRole ?? 'device_inference',
        },
        'findings': const <Map<String, dynamic>>[],
      },
    ];

    final notes = (doctorNotes ?? '').trim();
    final body = <String>[
      if (record.description.trim().isNotEmpty) record.description.trim(),
      if (notes.isNotEmpty) notes,
    ].join('\n');

    // The risk band is derived from confidence rather than asserted, so the
    // engine's label/score consistency check has something honest to compare.
    final double c = record.confidence;
    final String risk = c >= 0.85
        ? 'critical'
        : c >= 0.6
            ? 'high'
            : c >= 0.35
                ? 'moderate'
                : 'low';

    return <String, dynamic>{
      'kind': 'clinician_report',
      'subject': patientName ?? '',
      'title': record.className,
      'category': record.category,
      'riskLevel': risk,
      'score': c,
      'confidence': c,
      'body': body,
      'recommendations': const <String>[],
      'disclaimer': '',
      'evidence': evidence,
      'locale': 'en',
    };
  }
}
