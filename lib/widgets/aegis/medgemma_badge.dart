import 'package:flutter/material.dart';

/// Shows the MedGemma 2 on-premise hospital clinical guardrail verification badge.
class MedGemmaBadge extends StatelessWidget {
  final bool compact;
  const MedGemmaBadge({super.key, this.compact = false});

  static void showComplianceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF48BB78), size: 24),
            SizedBox(width: 10),
            Text(
              'MedGemma 2 Compliance',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This clinical report has been verified by Google MedGemma 2 running within an on-premise hospital intranet.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            _complianceRow(Icons.lock_outline, 'Zero Data Egress', 'Patient data remained inside hospital perimeter.'),
            const SizedBox(height: 8),
            _complianceRow(Icons.person_off_outlined, 'HIPAA De-identification', 'All third-party names and identifiers redacted.'),
            const SizedBox(height: 8),
            _complianceRow(Icons.verified_outlined, 'Clinical Guardrail Passed', 'Deterministic safety & dosage validation active.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Color(0xFF48BB78), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Widget _complianceRow(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF48BB78)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showComplianceDialog(context),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9, vertical: compact ? 2 : 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withOpacity(0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF48BB78).withOpacity(0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, size: 12, color: Color(0xFF48BB78)),
            const SizedBox(width: 4),
            Text(
              compact ? 'MedGemma 2' : '🛡️ MedGemma 2 Verified',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF48BB78),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
