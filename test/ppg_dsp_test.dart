import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/services/ppg_signal.dart';
import 'package:medicoscope/services/ppg_bp_analyzer.dart';

List<double> _deadPpg(int n) => List<double>.filled(n, 128.0);

List<double> _pulsatilePpg(double seconds, {double hrBpm = 72.0, double fps = 30.0}) {
  final n = (seconds * fps).round();
  final freq = hrBpm / 60.0;
  final out = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final t = i / fps;
    // Fundamental + first harmonic + dicrotic wave
    final ac = 3.0 * math.sin(2 * math.pi * freq * t) +
        1.5 * math.sin(4 * math.pi * freq * t + 0.5) +
        0.8 * math.sin(6 * math.pi * freq * t + 1.2);
    out[i] = 180.0 + ac; // DC level ~180
  }
  return out;
}

void main() {
  group('PpgSignal / PpgBpAnalyzer', () {
    test('rejects a too-short or flat capture', () {
      final f = PpgSignal.extract(raw: _deadPpg(20));
      expect(f.usable, isFalse);
    });

    test('rejects flat unmodulated signal', () {
      final f = PpgSignal.extract(raw: _deadPpg(300));
      expect(f.usable, isFalse);
    });

    test('extracts accurate cardiac rhythm and features from pulsatile PPG', () {
      final raw = _pulsatilePpg(12.0, hrBpm: 75.0);
      final f = PpgSignal.extract(raw: raw);
      expect(f.usable, isTrue);
      expect(f.hrBpm, inInclusiveRange(65.0, 85.0));
      expect(f.perfusionIndex, greaterThan(0));
      expect(f.nBeats, greaterThanOrEqualTo(1));
    });

    test('PpgBpAnalyzer estimates clinically sane BP from usable PPG', () {
      final raw = _pulsatilePpg(12.0, hrBpm: 72.0);
      final r = PpgBpAnalyzer.analyze(samples: raw);
      expect(r.disease, DiseaseType.hypertension);
      expect(r.findings, isNotEmpty);
      expect(r.score, inInclusiveRange(0.0, 1.0));

      final sbpFinding = r.findings.firstWhere((f) => f.name.contains('Systolic'));
      final dbpFinding = r.findings.firstWhere((f) => f.name.contains('Diastolic'));
      final sbp = double.parse(sbpFinding.value);
      final dbp = double.parse(dbpFinding.value);

      expect(sbp, inInclusiveRange(90.0, 160.0));
      expect(dbp, inInclusiveRange(60.0, 100.0));
      expect(sbp, greaterThan(dbp));
    });
  });

  group('Clinical Report Sanitization', () {
    test('removes all asterisks from markdown reports', () {
      const raw = '''**CLINICAL SUMMARY:**
* Patient is experiencing moderate distress.
* Recommended action: **immediate consultation**.
* Urgency level: moderate.''';

      var text = raw;
      text = text.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)?.trim() ?? '');
      text = text.replaceAllMapped(RegExp(r'(^|\n)\s*[*•-]\s+', multiLine: true), (m) => '${m.group(1)}• ');
      text = text.replaceAll('*', '').trim();

      expect(text.contains('*'), isFalse);
      expect(text, contains('CLINICAL SUMMARY:'));
      expect(text, contains('• Patient is experiencing moderate distress.'));
      expect(text, contains('immediate consultation'));
    });
  });
}
