import 'package:flutter_test/flutter_test.dart';
import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/detection_record.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/models/quality_gate_result.dart';
import 'package:medicoscope/services/quality/qg_content.dart';
import 'package:medicoscope/services/quality/qg_preflight.dart';
import 'package:medicoscope/services/quality_gate_service.dart';

/// Client-side Quality Gate tests.
///
/// These test the ONLY two things the app is responsible for:
///   1. the local pre-flight tells the truth about its own limits, and
///   2. domain models are translated into gate content without losing evidence.
///
/// The rules themselves are NOT tested here, on purpose. They live on the server
/// and are covered by the golden corpus, the determinism lock, the mutation
/// harness and the API contract test under `server/quality/harness/`. Testing a
/// second copy of the rules on the client would mean there was a second copy of
/// the rules on the client, which is the bug this change removed.
///
/// The previous version of this file asserted the old behaviour: five dimensions
/// always present, status always `passed`, a 16-character device-side hash, and a
/// "determinism benchmark" that looped a pure function and reported that it
/// agreed with itself. Every one of those assertions passed while the gate was
/// incapable of failing, which is a useful reminder that a green suite is only
/// as good as what it claims.
void main() {
  final record = DetectionRecord(
    id: 'test-rec-001',
    patientId: 'patient-123',
    performedBy: 'doc-456',
    category: 'skin',
    className: 'Melanocytic Nevi',
    confidence: 0.92,
    timestamp: DateTime(2026, 8, 22, 10, 30),
    description: 'Benign melanocytic proliferation on the dorsal forearm.',
  );

  group('Local pre-flight is honest about being provisional', () {
    test('never reports a pass, and issues no certificate', () {
      final r = QualityGateService.auditDetectionRecord(
        record: record,
        patientName: 'A. Patient',
        doctorNotes: 'Clinical impression consistent with a benign nevus. '
            'Follow-up recommended within 14 business days. Advise the patient '
            'to consult a physician if the lesion changes in size or colour.',
      );

      expect(r.isProvisional, isTrue);
      expect(r.isCertified, isFalse);
      expect(r.certificateId, isEmpty);
      expect(r.verdictDigest, isEmpty);
      // A pre-flight has no authority to pass anything.
      expect(r.status, isNot(QualityGateStatus.passed));
      expect(r.headline, contains('PROVISIONAL'));
      expect(r.sealLine, contains('not certified'));
    });

    test('omits the dimensions it cannot evaluate rather than scoring them', () {
      final r = QualityGateService.auditDetectionRecord(
        record: record,
        patientName: 'A. Patient',
        doctorNotes: 'Follow-up within 14 days.',
      );
      final types = r.dimensions.map((d) => d.type).toSet();

      // Safety and grounding need the evidence set and the policy pack, so the
      // pre-flight must not claim anything about them. A green bar for a check
      // that never ran is the failure this asserts against.
      expect(types.contains(QualityDimensionType.safety), isFalse);
      expect(types.contains(QualityDimensionType.grounding), isFalse);
      expect(types.contains(QualityDimensionType.structure), isTrue);
      expect(r.dimensions.every((d) => d.title.contains('pre-flight')), isTrue);
    });

    test('a device-side hash is never presented as a seal', () {
      final r = QualityGateService.auditScreeningResult(_screening());
      expect(r.auditHash, isNot(matches(RegExp(r'^[0-9A-F]{16}$'))));
      expect(r.isCertified, isFalse);
    });
  });

  group('Pre-flight catches the defects it claims to catch', () {
    QgPreflightResult run(String body,
            {List<String> recs = const <String>[], String disclaimer = ''}) =>
        QgPreflight.run(
          body: body,
          recommendations: recs,
          disclaimer: disclaimer,
        );

    test('leftover authoring placeholders', () {
      final r = run('The lesion appears benign on inspection and the margins '
          'are regular throughout. TODO: add the lifestyle guidance section '
          'before this goes out to the patient for review this week.');
      expect(
        r.failures.any((f) => f.checkId == 'STR_NO_PLACEHOLDERS'),
        isTrue,
      );
    });

    test('a body that stops mid-thought', () {
      final r = run('The lesion appears benign and the margins are regular, '
          'so the plan going forward is that the');
      expect(r.failures.any((f) => f.checkId == 'STR_NO_TRUNCATION'), isTrue);
    });

    test('advice with no deadline', () {
      final r = run(
        'The lesion appears benign on inspection and the margins are regular. '
        'Please arrange a review with your doctor at some point.',
        recs: <String>['Book a review appointment.'],
      );
      expect(r.failures.any((f) => f.checkId == 'ACT_TIMEFRAME'), isTrue);
    });

    test('a deadline is recognised when it is actually given', () {
      final r = run(
        'The lesion appears benign on inspection and the margins are regular. '
        'Please arrange a review with your doctor within 14 days so the site '
        'can be measured and photographed again for comparison.',
        recs: <String>['Book a review appointment within 14 days.'],
      );
      expect(r.failures.any((f) => f.checkId == 'ACT_TIMEFRAME'), isFalse);
    });

    test('repeated boilerplate', () {
      const line = 'This is a screening signal and not a diagnosis. ';
      final r = run('$line$line$line'
          'Please see your doctor within 7 days for a proper examination.');
      expect(
        r.failures.any((f) => f.checkId == 'STR_NO_DUPLICATE_SENTENCES'),
        isTrue,
      );
    });

    test('unglossed clinical vocabulary in patient-facing text', () {
      final r = QgPreflight.run(
        body: 'The trace shows tachycardia together with mild oedema, and the '
            'pattern has been stable across the last three recordings taken '
            'this week at home.',
        patientFacing: true,
      );
      expect(
        r.failures.any((f) => f.checkId == 'RDB_JARGON_GLOSSED'),
        isTrue,
      );
    });

    test('the same vocabulary is fine in a clinician note', () {
      final r = QgPreflight.run(
        body: 'The trace shows tachycardia together with mild oedema, and the '
            'pattern has been stable across the last three recordings.',
        patientFacing: false,
      );
      expect(
        r.failures.any((f) => f.checkId == 'RDB_JARGON_GLOSSED'),
        isFalse,
      );
    });
  });

  group('Readability is measured, not asserted', () {
    test('plain language scores lower than clinical prose', () {
      final plain = QgPreflight.fkGrade(
          'Your blood pressure was a little high. Please see a doctor soon.');
      final dense = QgPreflight.fkGrade(
          'Photoplethysmographic estimation demonstrated prehypertensive '
          'stratification necessitating confirmatory oscillometric '
          'sphygmomanometry.');
      expect(plain, lessThan(dense));
      // The old implementation returned one of four hard-coded strings from a
      // words-per-sentence lookup table, so it could not move at all.
      expect(dense, greaterThan(12));
    });

    test('empty text does not blow up', () {
      expect(QgPreflight.fkGrade(''), 0);
      expect(QgPreflight.fkGrade('   '), 0);
    });
  });

  group('Domain models translate into gate content without losing evidence', () {
    test('every numeric marker becomes a bindable evidence fact', () {
      final content = QgContent.fromScreeningResult(_screening());
      final evidence = content['evidence'] as List;
      expect(evidence, hasLength(1));

      final findings =
          (evidence.first as Map)['findings'] as List<Map<String, dynamic>>;
      final labels = findings.map((f) => f['label']).toList();
      expect(labels, contains('Systolic'));
      expect(labels, contains('Diastolic'));
      // 'Regular' is qualitative: it has no number, so it must NOT become a
      // numeric fact that a claim could spuriously bind to.
      expect(labels, isNot(contains('Rhythm')));

      final systolic =
          findings.firstWhere((f) => f['label'] == 'Systolic')['value'];
      expect(systolic, 128);
    });

    test('fidelity follows the modality, not the wish', () {
      expect(QgContent.fidelityForMethod(DetectionMethod.labReportPdf), 'real');
      expect(QgContent.fidelityForMethod(DetectionMethod.ppgBloodPressure),
          'heuristic');
      expect(QgContent.fidelityForMethod(DetectionMethod.respiratoryAcoustic),
          'fabricated_scale');
    });

    test('the reference range travels with the value into the narrative', () {
      final content = QgContent.fromScreeningResult(_screening());
      expect(content['body'], contains('reference range'));
      expect(content['body'], contains('not a diagnosis'));
    });

    test('marker values are parsed leniently but never invented', () {
      expect(QgContent.parseValue('128'), 128);
      expect(QgContent.parseValue('9.2 g/dL'), 9.2);
      expect(QgContent.parseValue('-1.5'), -1.5);
      expect(QgContent.parseValue('Regular'), isNull);
      expect(QgContent.parseValue(''), isNull);
    });

    test('the risk band derived from a record agrees with its confidence', () {
      final content = QgContent.fromDetectionRecord(record);
      // 0.92 confidence must not be described as low risk; the server's
      // risk-label consistency check would block that.
      expect(content['riskLevel'], 'critical');
      expect(content['score'], 0.92);
    });
  });
}

DiseaseRiskResult _screening() => DiseaseRiskResult(
      disease: DiseaseType.hypertension,
      method: DetectionMethod.ppgBloodPressure,
      risk: RiskLevel.high,
      score: 0.71,
      headline: 'Raised blood pressure estimate',
      findings: const <MarkerFinding>[
        MarkerFinding(
          name: 'Systolic',
          value: '128',
          unit: 'mmHg',
          referenceRange: '90-120',
          flag: 'high',
          interpretation: 'Above the normal range for an adult at rest.',
        ),
        MarkerFinding(
          name: 'Diastolic',
          value: '84',
          unit: 'mmHg',
          referenceRange: '60-80',
          flag: 'high',
          interpretation: 'Slightly above the normal range.',
        ),
        MarkerFinding(
          name: 'Rhythm',
          value: 'Regular',
          unit: '',
          referenceRange: 'Regular',
          flag: 'normal',
          interpretation: 'No irregularity detected in the pulse envelope.',
        ),
      ],
      topContributors: const <String>['systolic pressure', 'pulse transit time'],
      recommendations: const <String>[
        'Book a cuff blood pressure check with your doctor within 7 days.',
        'Repeat this scan each morning for a week and record the values.',
      ],
      dataSource: 'camera PPG, calibrated',
      timestamp: DateTime(2026, 8, 22, 10, 30),
    );
