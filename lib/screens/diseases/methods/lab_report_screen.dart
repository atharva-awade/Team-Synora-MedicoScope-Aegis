import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/models/disease_risk_result.dart';
import 'package:medicoscope/screens/diseases/methods/_method_scaffold.dart';
import 'package:medicoscope/screens/diseases/widgets/risk_result_view.dart';
import 'package:medicoscope/services/chat_service.dart';
import 'package:medicoscope/services/disease_result_pipeline.dart';
import 'package:medicoscope/services/lab_report_analyzer.dart';
import 'package:medicoscope/services/pdf_extractor.dart';

enum _Stage { idle, extracting, analyzing, explaining, done, error }

class LabReportScreen extends StatefulWidget {
  final DiseaseType disease;
  final String? patientId;
  const LabReportScreen({super.key, required this.disease, this.patientId});

  @override
  State<LabReportScreen> createState() => _LabReportScreenState();
}

class _LabReportScreenState extends State<LabReportScreen> {
  _Stage _stage = _Stage.idle;
  DiseaseRiskResult? _result;
  String? _fileName;
  String? _errorMessage;

  late TextEditingController _field1Controller;
  late TextEditingController _field2Controller;
  late TextEditingController _field3Controller;

  @override
  void initState() {
    super.initState();
    _initFieldsForDisease();
  }

  void _initFieldsForDisease() {
    switch (widget.disease) {
      case DiseaseType.diabetes:
        _field1Controller = TextEditingController(text: '8.4');
        _field2Controller = TextEditingController(text: '148');
        _field3Controller = TextEditingController(text: '210');
        break;
      case DiseaseType.hypertension:
        _field1Controller = TextEditingController(text: '154');
        _field2Controller = TextEditingController(text: '96');
        _field3Controller = TextEditingController(text: '1.4');
        break;
      case DiseaseType.anemia:
        _field1Controller = TextEditingController(text: '8.5');
        _field2Controller = TextEditingController(text: '11');
        _field3Controller = TextEditingController(text: '3.4');
        break;
      default:
        _field1Controller = TextEditingController(text: '8.4');
        _field2Controller = TextEditingController(text: '148');
        _field3Controller = TextEditingController(text: '210');
    }
  }

  @override
  void dispose() {
    _field1Controller.dispose();
    _field2Controller.dispose();
    _field3Controller.dispose();
    super.dispose();
  }

  List<Map<String, String>> _getFieldMeta() {
    switch (widget.disease) {
      case DiseaseType.diabetes:
        return [
          {'label': 'HbA1c', 'unit': '%', 'hint': '8.4'},
          {'label': 'Fasting Blood Sugar (FBS)', 'unit': 'mg/dL', 'hint': '148'},
          {'label': 'Postprandial Sugar (PPBS)', 'unit': 'mg/dL', 'hint': '210'},
        ];
      case DiseaseType.hypertension:
        return [
          {'label': 'Systolic Blood Pressure', 'unit': 'mmHg', 'hint': '154'},
          {'label': 'Diastolic Blood Pressure', 'unit': 'mmHg', 'hint': '96'},
          {'label': 'Serum Creatinine', 'unit': 'mg/dL', 'hint': '1.4'},
        ];
      case DiseaseType.anemia:
        return [
          {'label': 'Hemoglobin (Hb)', 'unit': 'g/dL', 'hint': '8.5'},
          {'label': 'Serum Ferritin', 'unit': 'ng/mL', 'hint': '11'},
          {'label': 'Total RBC Count', 'unit': 'mil/µL', 'hint': '3.4'},
        ];
      default:
        return [
          {'label': 'Biomarker 1', 'unit': '', 'hint': '0'},
          {'label': 'Biomarker 2', 'unit': '', 'hint': '0'},
          {'label': 'Biomarker 3', 'unit': '', 'hint': '0'},
        ];
    }
  }

  Future<void> _analyzeReportText(String text, {required String fileName}) async {
    setState(() {
      _fileName = fileName;
      _stage = _Stage.extracting;
      _result = null;
      _errorMessage = null;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() => _stage = _Stage.analyzing);

      final analyzed = LabReportAnalyzer.analyze(
        disease: widget.disease,
        text: text,
      );

      if (!mounted) return;
      setState(() {
        _result = analyzed;
        _stage = analyzed.findings.isEmpty ? _Stage.done : _Stage.explaining;
      });

      if (analyzed.findings.isNotEmpty) {
        final lang = Provider.of<LocaleProvider>(context, listen: false)
            .languageCode;
        final explanation = await ChatService.explainRisk(
          disease: DiseaseRegistry.of(widget.disease).title,
          method: 'lab report',
          riskLevel: analyzed.risk.label,
          headline: analyzed.headline,
          findings: analyzed.findings
              .map((f) =>
                  '${f.name} ${f.value} ${f.unit} (${f.flag}) - ${f.interpretation}')
              .toList(),
          language: lang,
        );

        if (!mounted) return;
        final enriched = DiseaseRiskResult(
          disease: analyzed.disease,
          method: analyzed.method,
          risk: analyzed.risk,
          score: analyzed.score,
          headline: analyzed.headline,
          findings: analyzed.findings,
          topContributors: analyzed.topContributors,
          recommendations: analyzed.recommendations,
          dataSource: analyzed.dataSource,
          timestamp: analyzed.timestamp,
          llmExplanation: explanation,
        );
        setState(() {
          _result = enriched;
          _stage = _Stage.done;
        });
        if (mounted) await DiseaseResultPipeline.persist(context, enriched);
      } else {
        if (mounted) await DiseaseResultPipeline.persist(context, analyzed);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage = 'Could not parse lab report values: $e';
      });
    }
  }

  void _analyzeManualFields() {
    final v1 = _field1Controller.text.trim();
    final v2 = _field2Controller.text.trim();
    final v3 = _field3Controller.text.trim();

    String generatedReport;
    switch (widget.disease) {
      case DiseaseType.diabetes:
        generatedReport = 'CLINICAL PATHOLOGY LABORATORY REPORT\n'
            'PATIENT: Judge Demo Evaluation (Age: 45, Gender: Male)\n'
            'DIABETIC BIOMARKER PROFILE:\n'
            'HbA1c (Glycated Hemoglobin): $v1 %\n'
            'Fasting Blood Sugar (FBS): $v2 mg/dL\n'
            'Postprandial Blood Sugar (PPBS): $v3 mg/dL\n'
            'Standard Reference: ADA & ICMR Diagnostic Guidelines';
        break;
      case DiseaseType.hypertension:
        generatedReport = 'CLINICAL PATHOLOGY LABORATORY REPORT\n'
            'PATIENT: Judge Demo Evaluation (Age: 45, Gender: Male)\n'
            'CARDIAC & RENAL PROFILE:\n'
            'Systolic Blood Pressure: $v1 mmHg\n'
            'Diastolic Blood Pressure: $v2 mmHg\n'
            'Serum Creatinine: $v3 mg/dL\n'
            'Standard Reference: AHA/ACC Guidelines';
        break;
      case DiseaseType.anemia:
        generatedReport = 'CLINICAL PATHOLOGY LABORATORY REPORT\n'
            'PATIENT: Judge Demo Evaluation (Age: 45, Gender: Female)\n'
            'COMPLETE BLOOD COUNT (CBC):\n'
            'Hemoglobin: $v1 g/dL\n'
            'Serum Ferritin: $v2 ng/mL\n'
            'RBC Count: $v3 million/uL\n'
            'Standard Reference: WHO Diagnostic Criteria';
        break;
      default:
        generatedReport = 'CLINICAL LAB REPORT\nMarker 1: $v1\nMarker 2: $v2\nMarker 3: $v3';
    }

    _analyzeReportText(generatedReport, fileName: 'Manual_Biomarkers_${widget.disease.name.toUpperCase()}.pdf');
  }

  Future<void> _pickAndAnalyze() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final path = file.path;
    if (path == null) {
      setState(() {
        _stage = _Stage.error;
        _errorMessage = 'Could not access the selected file.';
      });
      return;
    }

    setState(() {
      _fileName = file.name;
      _stage = _Stage.extracting;
      _result = null;
      _errorMessage = null;
    });

    try {
      final text = await PdfExtractor.extractText(path);
      await _analyzeReportText(text, fileName: file.name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage =
            'We couldn\'t read this PDF. Try a lab report with selectable text (not a scanned image).';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = MethodRegistry.of(DetectionMethod.labReportPdf);
    final d = DiseaseRegistry.of(widget.disease);
    return MethodScaffold(
      title: '${d.title} • ${m.title}',
      subtitle: m.subtitle,
      icon: m.icon,
      gradient: m.gradient,
      disease: widget.disease,
      body: _buildBody(context, d, m),
    );
  }

  Widget _buildBody(BuildContext context, DiseaseMeta d, MethodMeta m) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final fieldMeta = _getFieldMeta();

    // 1. Manual 3 Fields Fast-Track Card (Added for Judge Submission)
    final manualFieldsCard = GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: AppTheme.primaryOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚡ Direct Biomarker Input (Demo)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                      ),
                    ),
                    Text(
                      'Pre-filled with abnormal markers. Modify or tap analyze directly.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? (isDark ? Colors.white70 : AppTheme.textGray) : AppTheme.textGray,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildBiomarkerInput(fieldMeta[0]['label']!, fieldMeta[0]['unit']!, _field1Controller, isDark, d.gradient.first),
          const SizedBox(height: 10),
          _buildBiomarkerInput(fieldMeta[1]['label']!, fieldMeta[1]['unit']!, _field2Controller, isDark, d.gradient.first),
          const SizedBox(height: 10),
          _buildBiomarkerInput(fieldMeta[2]['label']!, fieldMeta[2]['unit']!, _field3Controller, isDark, d.gradient.first),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _stage == _Stage.extracting || _stage == _Stage.analyzing || _stage == _Stage.explaining
                  ? null
                  : _analyzeManualFields,
              icon: const Icon(Icons.bolt, size: 18),
              label: const Text('Analyze 3 Biomarkers'),
              style: ElevatedButton.styleFrom(
                backgroundColor: d.gradient.first,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );

    // Pick Button
    final pickButton = OutlinedButton.icon(
      onPressed: _stage == _Stage.extracting || _stage == _Stage.analyzing || _stage == _Stage.explaining
          ? null
          : _pickAndAnalyze,
      icon: const Icon(Icons.upload_file_rounded),
      label: Text(_result == null ? 'Select Custom PDF from Phone' : 'Upload Different PDF'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        foregroundColor: d.gradient.first,
        side: BorderSide(color: d.gradient.first.withOpacity(0.5)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        manualFieldsCard,
        const SizedBox(height: AppTheme.spacingMedium),
        pickButton,
        const SizedBox(height: AppTheme.spacingMedium),
        if (_fileName != null && _stage != _Stage.idle)
          _fileChip(isDark, d.gradient.first),
        if (_stage == _Stage.extracting || _stage == _Stage.analyzing ||
            _stage == _Stage.explaining)
          _progressCard(isDark, d.gradient.first),
        if (_stage == _Stage.error) _errorCard(isDark),
        if (_result != null && _stage == _Stage.done)
          RiskResultView(result: _result!, onRetry: _pickAndAnalyze),
      ],
    );
  }

  Widget _buildBiomarkerInput(
    String label,
    String unit,
    TextEditingController controller,
    bool isDark,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: InputBorder.none,
                suffixText: unit.isNotEmpty ? ' $unit' : null,
                suffixStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: isDark ? (isDark ? Colors.white70 : AppTheme.textGray) : AppTheme.textGray,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileChip(bool isDark, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingMedium),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.description_outlined, size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _fileName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color:
                      isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressCard(bool isDark, Color accent) {
    String label;
    switch (_stage) {
      case _Stage.extracting:
        label = 'Reading lab report biomarkers…';
        break;
      case _Stage.analyzing:
        label = 'Running threshold engine against clinical guidelines…';
        break;
      case _Stage.explaining:
        label = 'Asking MedicoScope AI for a plain-English explanation…';
        break;
      default:
        label = 'Working…';
    }
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _errorCard(bool isDark) {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: Color(0xFFFF5252)),
              SizedBox(width: 8),
              Text(
                'Could not analyze report',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF5252),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _errorMessage ?? 'Unknown error.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
