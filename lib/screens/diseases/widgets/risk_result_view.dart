import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/models/detection_record.dart';
import 'package:medicoscope/models/quality_gate_result.dart';
import 'package:medicoscope/services/quality_gate_service.dart';
import 'package:medicoscope/services/certified_report_pdf_service.dart';
import 'package:medicoscope/core/widgets/quality_gate_sheet.dart';

/// Unified result panel used by every detection method.
class RiskResultView extends StatelessWidget {
  final DiseaseRiskResult result;
  final VoidCallback? onRetry;

  const RiskResultView({super.key, required this.result, this.onRetry});

  Color _colorFor(RiskLevel r) {
    switch (r) {
      case RiskLevel.low:
        return const Color(0xFF4CAF50);
      case RiskLevel.moderate:
        return const Color(0xFFFF9800);
      case RiskLevel.high:
        return const Color(0xFFFF5252);
      case RiskLevel.critical:
        return const Color(0xFFD32F2F);
    }
  }

  IconData _flagIcon(String flag) {
    switch (flag) {
      case 'critical':
        return Icons.crisis_alert_rounded;
      case 'high':
        return Icons.trending_up_rounded;
      case 'low':
        return Icons.trending_down_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  Color _flagColor(String flag) {
    switch (flag) {
      case 'critical':
        return const Color(0xFFD32F2F);
      case 'high':
        return const Color(0xFFFF5252);
      case 'low':
        return const Color(0xFFFFA000);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  /// Ask the server engine for an authoritative verdict + certificate.
  ///
  /// If the gate is unreachable we return the PROVISIONAL pre-flight result
  /// unchanged and say so. We do not silently upgrade it: an offline device must
  /// not be able to manufacture a certification, because that is precisely the
  /// bypass an audit trail has to be immune to.
  Future<QualityGateResult> _certify(
    ScaffoldMessengerState messenger,
    QualityGateResult provisional,
  ) async {
    try {
      return await QualityGateService.certifyScreeningResult(result);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Quality Gate unreachable — showing the provisional pre-flight. '
              'Nothing has been certified.'),
          backgroundColor: Color(0xFFF39C12),
        ),
      );
      return provisional;
    }
  }

  /// Renders the ACTUAL state of a dimension.
  ///
  /// The previous version took a `passed` flag and ignored it, hard-coding a
  /// green tick and a green border for every pill. Five green ticks appeared
  /// whatever the content was, which made the row decorative rather than
  /// informative -- and decorative safety indicators are worse than none,
  /// because people believe them.
  Widget _miniDimPill(String label, bool passed, bool isDark) {
    final Color color =
        passed ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final meta = DiseaseRegistry.of(result.disease);
    final c = _colorFor(result.risk);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Headline / score card
        GlassCard(
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.withOpacity(0.4)),
                    ),
                    child: Text(
                      '${result.risk.label} RISK',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: c,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(result.score * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: c,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                result.headline,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: result.score.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor:
                      isDark ? Colors.white10 : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(c),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.science_outlined,
                      size: 13,
                      color:
                          isDark ? AppTheme.darkTextGray : AppTheme.textGray),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Source: ${result.dataSource}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppTheme.darkTextGray
                            : AppTheme.textGray,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),

        if (result.topContributors.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          GlassCard(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What drove this score',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.darkTextLight
                        : AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                ...result.topContributors.map(
                  (r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded,
                            size: 15, color: meta.gradient.first),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            r,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 100.ms, duration: 350.ms),
        ],

        if (result.findings.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          GlassCard(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Markers detected (${result.findings.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.darkTextLight
                        : AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                ...result.findings.map((f) {
                  final fc = _flagColor(f.flag);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_flagIcon(f.flag), size: 16, color: fc),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      f.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? AppTheme.darkTextLight
                                            : AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${f.value} ${f.unit}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: fc,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                f.interpretation,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: isDark
                                      ? AppTheme.darkTextGray
                                      : AppTheme.textGray,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Ref: ${f.referenceRange}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontStyle: FontStyle.italic,
                                  color: isDark
                                      ? AppTheme.darkTextGray
                                      : AppTheme.textGray,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
        ],

        if (result.recommendations.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          GlassCard(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.recommend_outlined,
                        size: 16, color: meta.gradient.first),
                    const SizedBox(width: 6),
                    Text(
                      'Recommendations',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextLight
                            : AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...result.recommendations.map((r) {
                  final urgent = r.startsWith('URGENT');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          urgent
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          size: 15,
                          color: urgent
                              ? const Color(0xFFFF5252)
                              : const Color(0xFF4ECDC4),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            r,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              fontWeight: urgent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: urgent
                                  ? const Color(0xFFFF5252)
                                  : isDark
                                      ? AppTheme.darkTextLight
                                      : AppTheme.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
        ],

        if (result.llmExplanation != null &&
            result.llmExplanation!.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          GlassCard(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 16, color: meta.gradient.first),
                    const SizedBox(width: 6),
                    Text(
                      'MedicoScope AI',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextLight
                            : AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  result.llmExplanation!,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: isDark
                        ? AppTheme.darkTextLight
                        : AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
        ],

        // Repeatable Quality Gate Certification Card (Patient & Clinical Grade)
        Builder(builder: (ctx) {
          final qg = QualityGateService.auditScreeningResult(result);
          final isPassed = qg.isPassed;
          final qgColor = isPassed ? const Color(0xFF2ECC71) : const Color(0xFFF39C12);

          return Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingMedium),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: qgColor.withOpacity(0.6), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: qgColor.withOpacity(0.15),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: GlassCard(
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [qgColor, qgColor.withOpacity(0.7)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.verified_rounded, size: 20, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      qg.isProvisional
                                          ? 'Quality Gate — not yet run'
                                          : 'Aegis Quality Gate ${qg.statusLabel}',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: qgColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: qgColor.withOpacity(0.4)),
                                    ),
                                    child: Text(
                                      qg.isProvisional
                                          ? 'PROVISIONAL'
                                          : '${qg.overallScorePercent}% · ${qg.certificateId}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                        color: qgColor,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                qg.isProvisional
                                    // Nothing has been certified yet, so the
                                    // card says so instead of showing a seal.
                                    ? 'Local pre-flight only. Tap Certify to have the '
                                        'server engine judge this against the evidence '
                                        'and issue a reproducible certificate.'
                                    : 'Judged by ${qg.packRef} • '
                                        '${qg.boundClaimCount}/${qg.claimCount} claims bound to evidence • '
                                        'seal ${qg.certificateId}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 5 Mini-Dimension Pills
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // Driven by the verdict, not by a literal `true`.
                        // A dimension the pre-flight could not evaluate is not
                        // shown at all rather than shown as passing.
                        ...qg.dimensions.map((d) => _miniDimPill(
                              '${d.title} ${d.scorePercent}%',
                              d.status != QualityGateStatus.blocked &&
                                  d.warnings.isEmpty &&
                                  d.criticalIssues.isEmpty,
                              isDark,
                            )),
                        _miniDimPill(
                          'Reading ${qg.readingGradeLevel}',
                          !qg.isProvisional,
                          isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    // Action Buttons for Patients
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(ctx);
                              final auth = Provider.of<AuthProvider>(ctx, listen: false);
                              final certified = await _certify(messenger, qg);
                              final realPatientName = (auth.user?.name != null && auth.user!.name.trim().isNotEmpty)
                                  ? auth.user!.name.trim()
                                  // A real person's name was hard-coded here as
                                  // the fallback. On any account without a name
                                  // set, that name was printed onto a clinical
                                  // PDF for a different patient.
                                  : 'Patient';
                              final patientCode = auth.user?.uniqueCode ?? auth.user?.id ?? 'MS-PAT-2026';
                              final scanTime = result.timestamp;

                              final dummyRecord = DetectionRecord(
                                id: 'REC-${scanTime.millisecondsSinceEpoch.toString().substring(5)}',
                                className: result.headline,
                                confidence: result.score,
                                category: result.disease.name,
                                performedBy: patientCode,
                                performedByName: realPatientName,
                                performedByRole: 'Patient Direct Encounter',
                                description: result.headline,
                                timestamp: scanTime,
                              );
                              CertifiedReportPdfService.generateAndSave(
                                record: dummyRecord,
                                patientName: realPatientName,
                                qualityResult: certified,
                                doctorNotes: result.recommendations.join('\n• '),
                              );
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(certified.isCertified
                                      ? 'PDF exported for $realPatientName — '
                                          'seal ${certified.certificateId} '
                                          '(${certified.statusLabel})'
                                      : 'PDF exported for $realPatientName — '
                                          'PROVISIONAL, no certificate issued'),
                                  backgroundColor: certified.isBlocked
                                      ? const Color(0xFFE74C3C)
                                      : const Color(0xFF2ECC71),
                                ),
                              );
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
                            label: const Text('Export PDF', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              side: BorderSide(color: const Color(0xFF667EEA).withOpacity(0.5)),
                              foregroundColor: const Color(0xFF667EEA),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(ctx);
                              final auth = Provider.of<AuthProvider>(ctx, listen: false);
                              final certified = await _certify(messenger, qg);
                              final realPatientName = (auth.user?.name != null && auth.user!.name.trim().isNotEmpty)
                                  ? auth.user!.name.trim()
                                  // A real person's name was hard-coded here as
                                  // the fallback. On any account without a name
                                  // set, that name was printed onto a clinical
                                  // PDF for a different patient.
                                  : 'Patient';
                              final patientCode = auth.user?.uniqueCode ?? auth.user?.id ?? 'MS-PAT-2026';
                              final scanTime = result.timestamp;

                              final dummyRecord = DetectionRecord(
                                id: 'REC-${scanTime.millisecondsSinceEpoch.toString().substring(5)}',
                                className: result.headline,
                                confidence: result.score,
                                category: result.disease.name,
                                performedBy: patientCode,
                                performedByName: realPatientName,
                                performedByRole: 'Patient Direct Encounter',
                                description: result.headline,
                                timestamp: scanTime,
                              );
                              // ignore: use_build_context_synchronously
                              QualityGateSheet.show(
                                ctx,
                                result: certified,
                                record: dummyRecord,
                                patientName: realPatientName,
                                doctorNotes: result.recommendations.join('\n• '),
                                title: 'Aegis Quality Gate Certificate',
                              );
                            },
                            icon: const Icon(Icons.shield_outlined, size: 15),
                            label: const Text('Certify & Inspect', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              backgroundColor: qgColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(delay: 400.ms, duration: 400.ms);
        }),

        if (onRetry != null) ...[
          const SizedBox(height: AppTheme.spacingLarge),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Run again'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: meta.gradient.first.withOpacity(0.5)),
            ),
          ),
        ],
      ],
    );
  }
}
