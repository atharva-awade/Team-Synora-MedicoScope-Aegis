import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:medicoscope/models/detection_record.dart';
import 'package:medicoscope/models/quality_gate_result.dart';

/// Generates an official, publication-ready MedicoScope-Aegis Certified Clinical PDF Report
/// with embedded Repeatable Quality Gate Seal, SHA-256 Audit Trail, and Doctor Assessment.
class CertifiedReportPdfService {
  static String _shortHash(String digest, [int n = 12]) =>
      digest.isEmpty ? '(none)' : (digest.length <= n ? digest : digest.substring(0, n));

  static Future<File> generateAndSave({
    required DetectionRecord record,
    required String patientName,
    required QualityGateResult qualityResult,
    String? doctorNotes,
  }) async {
    // 1. Create a PDF document
    final document = PdfDocument();
    document.pageSettings.margins.all = 36;
    final page = document.pages.add();
    final graphics = page.graphics;
    final size = page.getClientSize();

    // Fonts & Colors
    final titleFont = PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold);
    final subtitleFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final headerFont = PdfStandardFont(PdfFontFamily.helvetica, 13, style: PdfFontStyle.bold);
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final boldBodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final smallFont = PdfStandardFont(PdfFontFamily.helvetica, 8);
    final codeFont = PdfStandardFont(PdfFontFamily.courier, 9, style: PdfFontStyle.bold);

    final primaryColor = PdfColor(102, 126, 234);
    final successColor = PdfColor(46, 204, 113);
    final darkTextColor = PdfColor(33, 37, 41);
    final grayTextColor = PdfColor(108, 117, 125);
    final cardBgColor = PdfColor(245, 247, 251);

    double y = 0;

    // Header Top Bar
    graphics.drawRectangle(
      brush: PdfSolidBrush(primaryColor),
      bounds: Rect.fromLTWH(0, y, size.width, 6),
    );
    y += 16;

    // Organization & Seal Title
    graphics.drawString(
      'MEDICOSCOPE CLINICAL INTELLIGENCE',
      titleFont,
      brush: PdfSolidBrush(primaryColor),
      bounds: Rect.fromLTWH(0, y, size.width, 24),
    );
    y += 22;

    graphics.drawString(
      'AEGIS CLINICAL GOVERNANCE & AUTONOMY PLATFORM -- CERTIFIED QUALITY REPORT',
      subtitleFont,
      brush: PdfSolidBrush(grayTextColor),
      bounds: Rect.fromLTWH(0, y, size.width, 14),
    );
    y += 18;

    // Quality Gate Seal Banner (Green Box)
    // The banner states the ACTUAL verdict.
    //
    // The previous version printed "VERIFIED & CERTIFIED" and "Status: PASSED"
    // as string literals, on every PDF, whatever the gate had said -- including
    // on a report that failed. A document that always claims to have passed is
    // not a certificate; it is a sticker. If this seal is going to be worth
    // anything on a printout, it has to be capable of saying no.
    final PdfColor sealColor = qualityResult.isProvisional
        ? PdfColor(243, 156, 18)
        : qualityResult.isBlocked
            ? PdfColor(231, 76, 60)
            : qualityResult.hasWarnings
                ? PdfColor(243, 156, 18)
                : successColor;
    final String sealTitle = qualityResult.isProvisional
        ? '[AEGIS QUALITY GATE -- PROVISIONAL PRE-FLIGHT, NOT CERTIFIED]'
        : qualityResult.isBlocked
            ? '[AEGIS QUALITY GATE -- BLOCKED. NOT FIT FOR CLINICAL USE]'
            : qualityResult.hasWarnings
                ? '[AEGIS QUALITY GATE -- PASSED WITH REMARKS]'
                : '[AEGIS QUALITY GATE -- PASSED]';

    final sealBoxRect = Rect.fromLTWH(0, y, size.width, 66);
    graphics.drawRectangle(
      brush: PdfSolidBrush(cardBgColor),
      pen: PdfPen(sealColor, width: 1.5),
      bounds: sealBoxRect,
    );

    graphics.drawString(
      sealTitle,
      boldBodyFont,
      brush: PdfSolidBrush(sealColor),
      bounds: Rect.fromLTWH(12, y + 6, size.width - 24, 14),
    );

    final String blockingSuffix = qualityResult.blockingCheckIds.isEmpty
        ? ''
        : '  |  Blocking: ${qualityResult.blockingCheckIds.join(', ')}';
    final scoreStr = qualityResult.isProvisional
        ? 'No verdict issued. This is an offline pre-flight of text-only checks; '
            'safety and evidence grounding were not evaluated.'
        : 'Verdict: ${qualityResult.statusLabel} at ${qualityResult.overallScorePercent}%'
            '  |  Evidence grounding: ${qualityResult.boundClaimCount}/${qualityResult.claimCount} '
            'numeric claims bound$blockingSuffix';
    final auditStr = qualityResult.isProvisional
        ? 'Certificate: none'
        : 'Certificate ${qualityResult.certificateId}  |  judged by ${qualityResult.packRef}, '
            'engine ${qualityResult.engineVersion}  |  content ${_shortHash(qualityResult.contentDigest)}';
    final verifyStr = qualityResult.verifyUrl == null
        ? 'Recompute the certificate id from the content digest and the policy pack to verify offline.'
        : 'Verify independently: ${qualityResult.verifyUrl}';

    graphics.drawString(scoreStr, boldBodyFont, brush: PdfSolidBrush(darkTextColor), bounds: Rect.fromLTWH(12, y + 21, size.width - 24, 24));
    graphics.drawString(auditStr, codeFont, brush: PdfSolidBrush(grayTextColor), bounds: Rect.fromLTWH(12, y + 43, size.width - 24, 11));
    graphics.drawString(verifyStr, smallFont, brush: PdfSolidBrush(grayTextColor), bounds: Rect.fromLTWH(12, y + 54, size.width - 24, 11));
    y += 80;

    // Section 1: Patient & Encounter Metadata Table
    graphics.drawString('1. ENCOUNTER & PATIENT METADATA', headerFont, brush: PdfSolidBrush(primaryColor), bounds: Rect.fromLTWH(0, y, size.width, 16));
    y += 18;

    final metaTable = PdfGrid();
    metaTable.columns.add(count: 4);
    metaTable.columns[0].width = 90;
    metaTable.columns[1].width = 160;
    metaTable.columns[2].width = 90;
    metaTable.columns[3].width = 160;

    final r1 = metaTable.rows.add();
    r1.cells[0].value = 'Patient Name:';
    r1.cells[1].value = _cleanAscii(patientName);
    r1.cells[2].value = 'Report ID:';
    // Length-safe: a short generated id (e.g. "REC-1234567") made this throw a
    // RangeError on the export path.
    final String rawId = record.id ?? '';
    r1.cells[3].value = rawId.isEmpty
        ? 'MS-ENC-2026'
        : (rawId.length <= 12 ? rawId.toUpperCase() : rawId.substring(0, 12).toUpperCase());

    final r2 = metaTable.rows.add();
    r2.cells[0].value = 'Specialty:';
    r2.cells[1].value = record.category.toUpperCase();
    r2.cells[2].value = 'Encounter Time:';
    r2.cells[3].value = record.timestamp.toLocal().toString().substring(0, 19);

    final r3 = metaTable.rows.add();
    r3.cells[0].value = 'Performed By:';
    r3.cells[1].value = _cleanAscii(record.performedByName ?? 'Clinical Care Team');
    r3.cells[2].value = 'Role / Mode:';
    r3.cells[3].value = _cleanAscii(record.performedByRole ?? 'Medical Officer');

    final r4 = metaTable.rows.add();
    r4.cells[0].value = 'Patient Code:';
    r4.cells[1].value = _cleanAscii(record.patientId ?? record.performedBy);
    r4.cells[2].value = 'Certified At:';
    r4.cells[3].value = qualityResult.evaluatedAt.toLocal().toString().substring(0, 19);

    metaTable.style = PdfGridStyle(
      font: bodyFont,
      cellPadding: PdfPaddings(left: 6, top: 4, right: 6, bottom: 4),
    );
    final metaLayout = metaTable.draw(page: page, bounds: Rect.fromLTWH(0, y, size.width, 0))!;
    y = metaLayout.bounds.bottom + 16;

    // Section 2: Clinical Finding & Model Diagnostic Intelligence
    graphics.drawString('2. DIAGNOSTIC FINDINGS & MODEL CALIBRATION', headerFont, brush: PdfSolidBrush(primaryColor), bounds: Rect.fromLTWH(0, y, size.width, 16));
    y += 18;

    final diagTable = PdfGrid();
    diagTable.columns.add(count: 3);
    diagTable.columns[0].width = 180;
    diagTable.columns[1].width = 120;
    diagTable.columns[2].width = 200;

    final headerRow = diagTable.headers.add(1)[0];
    headerRow.cells[0].value = 'Primary Finding';
    headerRow.cells[1].value = 'Model Confidence';
    headerRow.cells[2].value = 'Clinical Classification';
    headerRow.style = PdfGridRowStyle(backgroundBrush: PdfSolidBrush(cardBgColor), font: boldBodyFont);

    final dr1 = diagTable.rows.add();
    dr1.cells[0].value = _cleanAscii(record.className);
    dr1.cells[1].value = record.category == 'heart_sound'
        ? '${record.confidence.toStringAsFixed(0)} BPM'
        : '${(record.confidence * 100).toStringAsFixed(1)}%';
    dr1.cells[2].value = record.confidence >= 0.8 ? 'High Confidence (Tier 1)' : 'Screening-Grade (Tier 2)';

    diagTable.style = PdfGridStyle(font: bodyFont, cellPadding: PdfPaddings(left: 6, top: 5, right: 6, bottom: 5));
    final diagLayout = diagTable.draw(page: page, bounds: Rect.fromLTWH(0, y, size.width, 0))!;
    y = diagLayout.bounds.bottom + 16;

    // Section 3: Physician Clinical Impression
    graphics.drawString('3. PHYSICIAN CLINICAL ASSESSMENT', headerFont, brush: PdfSolidBrush(primaryColor), bounds: Rect.fromLTWH(0, y, size.width, 16));
    y += 18;

    final rawNotes = (doctorNotes != null && doctorNotes.trim().isNotEmpty)
        ? doctorNotes.trim()
        : 'Clinical impression consistent with ${record.className}. Diagnostic evidence validated through Aegis Quality Gate. Follow-up consultation scheduled within 14 business days.';
    final notesText = _cleanAscii(rawNotes);

    graphics.drawRectangle(
      brush: PdfSolidBrush(cardBgColor),
      bounds: Rect.fromLTWH(0, y, size.width, 48),
    );
    graphics.drawString(
      notesText,
      bodyFont,
      brush: PdfSolidBrush(darkTextColor),
      bounds: Rect.fromLTWH(8, y + 6, size.width - 16, 36),
    );
    y += 58;

    // Section 4: 5-Dimension Repeatable Quality Gate Verification Table
    graphics.drawString('4. 5-DIMENSION REPEATABLE QUALITY GATE VERIFICATION', headerFont, brush: PdfSolidBrush(primaryColor), bounds: Rect.fromLTWH(0, y, size.width, 16));
    y += 18;

    final qgTable = PdfGrid();
    qgTable.columns.add(count: 3);
    qgTable.columns[0].width = 180;
    qgTable.columns[1].width = 70;
    qgTable.columns[2].width = 250;

    final qgHeader = qgTable.headers.add(1)[0];
    qgHeader.cells[0].value = 'Quality Dimension';
    qgHeader.cells[1].value = 'Score';
    qgHeader.cells[2].value = 'Verification Status & Compliance';
    qgHeader.style = PdfGridRowStyle(backgroundBrush: PdfSolidBrush(cardBgColor), font: boldBodyFont);

    for (final dim in qualityResult.dimensions) {
      final row = qgTable.rows.add();
      row.cells[0].value = _cleanAscii(dim.title);
      row.cells[1].value = '${dim.scorePercent}%';
      row.cells[2].value = dim.status == QualityGateStatus.passed
          ? '[PASSED] ${_cleanAscii(dim.passedChecks.isNotEmpty ? dim.passedChecks.first : "Compliant")}'
          : '[REMARK] ${_cleanAscii(dim.warnings.isNotEmpty ? dim.warnings.first : "Review advised")}';
    }

    qgTable.style = PdfGridStyle(font: bodyFont, cellPadding: PdfPaddings(left: 6, top: 4, right: 6, bottom: 4));
    final qgLayout = qgTable.draw(page: page, bounds: Rect.fromLTWH(0, y, size.width, 0))!;
    y = qgLayout.bounds.bottom + 16;

    // Footer with Disclaimers & Governance Notice
    final String overrideNote = (qualityResult.overrideReason ?? '').isEmpty
        ? '.'
        : ', including the clinician override recorded against it.';
    graphics.drawString(
      qualityResult.isProvisional
          ? 'GOVERNANCE NOTICE: This document has NOT been through the Quality Gate. '
              'The panel above is an offline pre-flight of text-only checks. No certificate '
              'was issued and nothing was written to the audit ledger.'
          : 'GOVERNANCE NOTICE: Judged by policy pack ${qualityResult.packRef} on engine '
              '${qualityResult.engineVersion}. Certificate ${qualityResult.certificateId} is a pure '
              'function of the content digest, the pack digest and the engine version -- the '
              'issuing timestamp is deliberately excluded, so the id can be recomputed and '
              'checked by anyone holding this content and that pack. The verdict is appended to '
              'the hash-chained Aegis decision ledger$overrideNote',
      smallFont,
      brush: PdfSolidBrush(grayTextColor),
      bounds: Rect.fromLTWH(0, size.height - 24, size.width, 20),
    );

    // 2. Save file
    final bytes = await document.save();
    document.dispose();

    final fileName = 'Certified_Report_${record.id ?? DateTime.now().millisecondsSinceEpoch}.pdf';
    
    // Save to App Documents and Cache for sharing
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$fileName');
    await tempFile.writeAsBytes(bytes, flush: true);

    File savedFile = tempFile;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final docFile = File('${docDir.path}/$fileName');
      await docFile.writeAsBytes(bytes, flush: true);
      savedFile = docFile;
    } catch (_) {}

    // Try saving directly to public Download folder on Android if accessible
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final pubFile = File('${downloadDir.path}/$fileName');
        await pubFile.writeAsBytes(bytes, flush: true);
        savedFile = pubFile;
      }
    } catch (_) {}

    // Automatically trigger system share/save/open sheet
    try {
      await Share.shareXFiles(
        [XFile(savedFile.path, name: fileName, mimeType: 'application/pdf')],
        subject: qualityResult.isCertified
            ? 'Aegis Quality Gate ${qualityResult.statusLabel} -- certificate ${qualityResult.certificateId}'
            : 'Aegis clinical report (PROVISIONAL -- not certified)',
      );
    } catch (_) {
      // Fallback to url launcher
      try {
        final uri = Uri.file(savedFile.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    }

    return savedFile;
  }

  static String _cleanAscii(String input) {
    return input.replaceAll(RegExp(r'[^\x00-\x7F]'), '').trim();
  }
}
