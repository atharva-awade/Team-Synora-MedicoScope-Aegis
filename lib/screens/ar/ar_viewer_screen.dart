import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/services/ar_service.dart';

class ArViewerScreen extends StatefulWidget {
  final String modelPath;
  final String title;
  final double confidence;

  const ArViewerScreen({
    super.key,
    required this.modelPath,
    required this.title,
    this.confidence = 0.0,
  });

  @override
  State<ArViewerScreen> createState() => _ArViewerScreenState();
}

class _ArViewerScreenState extends State<ArViewerScreen>
    with WidgetsBindingObserver {
  bool _autoRotate = true;
  Key _modelKey = UniqueKey();
  bool _isBackgrounded = false;
  bool _isLaunchingAR = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (mounted) setState(() => _isBackgrounded = true);
    } else if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() => _isBackgrounded = false);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _resetModel() {
    setState(() {
      _modelKey = UniqueKey();
    });
  }

  void _toggleAutoRotate() {
    setState(() {
      _autoRotate = !_autoRotate;
    });
  }

  Future<void> _launchAR() async {
    if (_isLaunchingAR || widget.modelPath.isEmpty) return;
    setState(() => _isLaunchingAR = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Launching Google AR for ${widget.title}...',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: AppTheme.primaryOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    try {
      final success = await ARService.launchARViewer(
        widget.modelPath,
        title: widget.title,
      );
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ARService.getARSupportMessage()),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _isLaunchingAR = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            _buildTopBar(context),

            // Main Interactive 3D Viewport
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF1E293B),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      // Layer 1: Hologram Grid Platform
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _HologramGridPainter(),
                        ),
                      ),

                      // Layer 2: Interactive 3D Model
                      Positioned.fill(
                        child: (_isBackgrounded || _isLaunchingAR)
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.view_in_ar_rounded,
                                      size: 56,
                                      color: AppTheme.primaryOrange,
                                    ),
                                    SizedBox(height: 14),
                                    Text(
                                      'Google AR Active in Physical Space',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ModelViewer(
                                key: _modelKey,
                                src: widget.modelPath,
                                alt: '3D model of ${widget.title}',
                                ar: false,
                                cameraControls: true,
                                autoRotate: _autoRotate,
                                autoRotateDelay: 0,
                                rotationPerSecond: '25deg',
                                backgroundColor: Colors.transparent,
                              ),
                      ),

                      // Layer 3: Status Badge
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B0F19).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.primaryOrange,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '3D Model View',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Layer 4: Interaction Hint
                      Positioned(
                        bottom: 12,
                        left: 16,
                        right: 16,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B0F19).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.threed_rotation_rounded,
                                  color: Colors.white70,
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Drag to rotate 360° • Pinch to zoom lesion',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Controls Bar
            _buildBottomControls(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _buildCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF161F2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primaryOrange,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '3D AR Inspection Active${widget.confidence > 0 ? " • ${(widget.confidence * 100).toStringAsFixed(1)}%" : ""}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildCircleButton(
            icon: Icons.refresh_rounded,
            iconColor: AppTheme.primaryOrange,
            onTap: _resetModel,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161F2E),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionItem(
            icon: Icons.restart_alt_rounded,
            label: 'Reset',
            onTap: _resetModel,
          ),
          Container(
            width: 1,
            height: 28,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          _buildActionItem(
            icon: _autoRotate
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_filled_rounded,
            iconColor: _autoRotate ? AppTheme.primaryOrange : Colors.white70,
            label: _autoRotate ? 'Pause' : 'Rotate',
            onTap: _toggleAutoRotate,
          ),
          Container(
            width: 1,
            height: 28,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          _buildActionItem(
            icon: Icons.view_in_ar_rounded,
            iconColor: const Color(0xFF00E676),
            label: _isLaunchingAR ? 'Launching...' : 'Project in Room',
            onTap: _isLaunchingAR ? () {} : _launchAR,
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.white70,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: iconColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF161F2E),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
    );
  }
}

class _HologramGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.3)
      ..strokeWidth = 1.0;

    const step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
