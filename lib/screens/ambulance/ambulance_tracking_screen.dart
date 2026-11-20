import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/models/ambulance_booking_model.dart';
import 'package:medicoscope/services/ambulance_service.dart';

class AmbulanceTrackingScreen extends StatefulWidget {
  final AmbulanceBooking booking;

  const AmbulanceTrackingScreen({super.key, required this.booking});

  @override
  State<AmbulanceTrackingScreen> createState() => _AmbulanceTrackingScreenState();
}

class _AmbulanceTrackingScreenState extends State<AmbulanceTrackingScreen>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  late List<LatLng> _routePoints;
  int _currentStepIndex = 0;
  Timer? _simulationTimer;
  late double _distanceKmRemaining;
  late int _etaMinutesRemaining;
  bool _hasArrived = false;
  late AnimationController _pulseAnimCtrl;

  // Heading & 3D visualization states
  double _currentBearing = 0.0;
  bool _use3DMarker = false;
  bool _show3dCard = true;
  bool _autoCenter = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    // Strobe / pulse animation controller for emergency lightbar & beacons
    _pulseAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    final hospLatLng = LatLng(
      widget.booking.hospitalLatitude,
      widget.booking.hospitalLongitude,
    );
    final patLatLng = LatLng(
      widget.booking.patientLatitude,
      widget.booking.patientLongitude,
    );

    // Initialize baseline corridor immediately for instantaneous render
    _routePoints = AmbulanceService.generateRouteCoordinates(
      start: hospLatLng,
      end: patLatLng,
      steps: 60,
    );

    // Fetch actual real-world street route from OSRM following authentic roads
    AmbulanceService.fetchRealisticStreetRoute(
      start: hospLatLng,
      end: patLatLng,
    ).then((actualStreetPoints) {
      if (mounted && actualStreetPoints.length >= 2) {
        setState(() {
          _routePoints = actualStreetPoints;
          _currentStepIndex = 0;
          if (_routePoints.length > 1) {
            _currentBearing = AmbulanceService.calculateBearing(
              _routePoints[0],
              _routePoints[1],
            );
          }
        });
      }
    });

    // Calculate initial forward heading toward first waypoint
    if (_routePoints.length > 1) {
      _currentBearing = AmbulanceService.calculateBearing(
        _routePoints[0],
        _routePoints[1],
      );
    }

    _distanceKmRemaining = const Distance().as(
      LengthUnit.Kilometer,
      hospLatLng,
      patLatLng,
    );
    if (_distanceKmRemaining < 0.5) _distanceKmRemaining = 2.4;
    _etaMinutesRemaining = widget.booking.initialEtaMinutes;

    _startAmbulanceSimulation();
  }

  /// Smooth, natural paced ambulance motion with interpolated heading
  void _startAmbulanceSimulation() {
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (_currentStepIndex < _routePoints.length - 1) {
        setState(() {
          _currentStepIndex++;

          // Update heading so vehicle and headlights point along current road segment
          final pNow = _routePoints[_currentStepIndex];
          final pNext = (_currentStepIndex < _routePoints.length - 1)
              ? _routePoints[_currentStepIndex + 1]
              : _routePoints[_currentStepIndex];

          final targetBearing = AmbulanceService.calculateBearing(pNow, pNext);
          // Shortest-distance angle interpolation
          final diff = (targetBearing - _currentBearing + math.pi) % (2 * math.pi) - math.pi;
          _currentBearing += diff * 0.85;

          final progressRatio = _currentStepIndex / (_routePoints.length - 1);
          _distanceKmRemaining =
              (1.0 - progressRatio) * (widget.booking.initialEtaMinutes * 0.4);
          _etaMinutesRemaining = ((1.0 - progressRatio) *
                  widget.booking.initialEtaMinutes)
              .ceil();

          if (_etaMinutesRemaining <= 0) _etaMinutesRemaining = 1;
        });

        // Gently keep map camera centered only when auto-center is enabled
        if (_autoCenter && _currentStepIndex % 2 == 0) {
          final currentPos = _routePoints[_currentStepIndex];
          _mapController.move(currentPos, _mapController.camera.zoom);
        }
      } else {
        timer.cancel();
        setState(() {
          _hasArrived = true;
          _distanceKmRemaining = 0.0;
          _etaMinutesRemaining = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _pulseAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:${clean.isNotEmpty ? clean : "108"}');
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Emergency Ambulance?'),
        content: const Text(
          'Are you sure you want to cancel the dispatched ambulance? Only cancel if you are safe and medical assistance is no longer required.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Dispatched'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              _simulationTimer?.cancel();
              Navigator.pop(ctx);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ambulance mission has been cancelled.'),
                  backgroundColor: Colors.blueGrey,
                ),
              );
            },
            child: const Text('Yes, Cancel Ambulance'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentAmbPos = _routePoints[_currentStepIndex];
    final patientPos = LatLng(
      widget.booking.patientLatitude,
      widget.booking.patientLongitude,
    );
    final hospitalPos = LatLng(
      widget.booking.hospitalLatitude,
      widget.booking.hospitalLongitude,
    );

    return Scaffold(
      body: Stack(
        children: [
          // 1. Live Interactive Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentAmbPos,
              initialZoom: 15.0,
              minZoom: 11.0,
              maxZoom: 18.0,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _autoCenter) {
                  setState(() => _autoCenter = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.medicoscope.aegis',
              ),
              PolylineLayer(
                polylines: [
                  // Full planned corridor
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5.0,
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.30),
                  ),
                  // Active route driven so far
                  Polyline(
                    points: _routePoints.sublist(0, _currentStepIndex + 1),
                    strokeWidth: 6.0,
                    color: const Color(0xFFFF3B30),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // Hospital Marker
                  Marker(
                    point: hospitalPos,
                    width: 48,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_hospital_rounded,
                        color: Color(0xFF4CAF50),
                        size: 28,
                      ),
                    ),
                  ),

                  // Patient GPS Location Marker
                  Marker(
                    point: patientPos,
                    width: 56,
                    height: 56,
                    child: AnimatedBuilder(
                      animation: _pulseAnimCtrl,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF2196F3).withValues(
                              alpha: 0.2 + (_pulseAnimCtrl.value * 0.2),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF2196F3),
                              ),
                              child: const Icon(
                                Icons.person_pin_circle,
                                color: Colors.white,
                                size: 15,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Moving Ambulance Marker (Directional Top-View with Headlights or 3D Model)
                  Marker(
                    point: currentAmbPos,
                    width: 72,
                    height: 96,
                    alignment: Alignment.center,
                    child: _use3DMarker
                        ? _build3DMapMarker()
                        : _buildTopViewAmbulanceMarker(),
                  ),
                ],
              ),
            ],
          ),

          // 2. Top Header Bar & View Switcher
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: (isDark ? AppTheme.darkCard : Colors.white)
                            .withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_outlined,
                              color: Color(0xFFFF3B30), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _hasArrived
                                  ? 'AMBULANCE ARRIVED [SIMULATION]'
                                  : 'AMBULANCE EN ROUTE [SIMULATION]',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                                color: Color(0xFFFF3B30),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Marker Mode Toggle: Top-Down vs 3D Model
                  InkWell(
                    onTap: () => setState(() => _use3DMarker = !_use3DMarker),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        color: _use3DMarker
                            ? const Color(0xFFFF3B30)
                            : (isDark ? AppTheme.darkCard : Colors.white),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 8),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _use3DMarker
                                ? Icons.view_in_ar_rounded
                                : Icons.navigation_rounded,
                            size: 16,
                            color: _use3DMarker
                                ? Colors.white
                                : (isDark ? AppTheme.darkTextLight : AppTheme.textDark),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _use3DMarker ? '3D' : 'Road',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: _use3DMarker
                                  ? Colors.white
                                  : (isDark ? AppTheme.darkTextLight : AppTheme.textDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2.5 Floating Interactive Map Controls (Zoom +, Zoom -, Re-center Ambulance, My Location, View Route)
          Positioned(
            right: 16,
            top: 75,
            child: Column(
              children: [
                _buildMapActionButton(
                  icon: Icons.add,
                  tooltip: 'Zoom In',
                  onTap: () {
                    final z = (_mapController.camera.zoom + 1.0).clamp(11.0, 18.0);
                    _mapController.move(_mapController.camera.center, z);
                  },
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _buildMapActionButton(
                  icon: Icons.remove,
                  tooltip: 'Zoom Out',
                  onTap: () {
                    final z = (_mapController.camera.zoom - 1.0).clamp(11.0, 18.0);
                    _mapController.move(_mapController.camera.center, z);
                  },
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _buildMapActionButton(
                  icon: Icons.navigation_rounded,
                  tooltip: _autoCenter ? 'Tracking Ambulance (Tap to unlock)' : 'Follow Ambulance',
                  active: _autoCenter,
                  activeColor: const Color(0xFFFF3B30),
                  onTap: () {
                    setState(() => _autoCenter = !_autoCenter);
                    if (_autoCenter && _currentStepIndex < _routePoints.length) {
                      _mapController.move(_routePoints[_currentStepIndex], 16.0);
                    }
                  },
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _buildMapActionButton(
                  icon: Icons.person_pin_circle_rounded,
                  tooltip: 'Center on My Location',
                  activeColor: const Color(0xFF2196F3),
                  onTap: () {
                    setState(() => _autoCenter = false);
                    _mapController.move(patientPos, 16.0);
                  },
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _buildMapActionButton(
                  icon: Icons.alt_route_rounded,
                  tooltip: 'View Full Route',
                  onTap: () {
                    setState(() => _autoCenter = false);
                    _mapController.fitCamera(
                      CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(_routePoints),
                        padding: const EdgeInsets.fromLTRB(40, 110, 40, 360),
                      ),
                    );
                  },
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // 3. Bottom Real-Time Telemetry & 3D Vehicle Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.52,
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B1B1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 25,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle Bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // ETA and Distance Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _hasArrived ? 'ARRIVED' : '$_etaMinutesRemaining MINS',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFFF3B30),
                              ),
                            ),
                            Text(
                              _hasArrived
                                  ? 'Paramedics outside your location'
                                  : 'ESTIMATED ARRIVAL TIME',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: isDark ? AppTheme.darkTextDim : AppTheme.textGray,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.near_me_outlined,
                                  color: Color(0xFFFF3B30), size: 15),
                              const SizedBox(width: 5),
                              Text(
                                '${_distanceKmRemaining.toStringAsFixed(1)} km away',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFFF3B30),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // 3D Model Ambulance Inspection Card (using ambulance.glb)
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                            child: Row(
                              children: [
                                const Icon(Icons.view_in_ar_rounded,
                                    size: 16, color: Color(0xFFFF3B30)),
                                const SizedBox(width: 6),
                                Text(
                                  '3D Ambulance Unit • ${widget.booking.vehicleNumber}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? AppTheme.darkTextLight
                                        : AppTheme.textDark,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.open_in_full, size: 16, color: Color(0xFFFF3B30)),
                                  tooltip: 'Open 3D Vehicle Full Window',
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  onPressed: _open3DAmbulanceFullScreenModal,
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => setState(() => _show3dCard = !_show3dCard),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      _show3dCard
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      size: 18,
                                      color: isDark ? AppTheme.darkTextDim : AppTheme.textGray,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_show3dCard)
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                              child: Container(
                                height: 130,
                                width: double.infinity,
                                color: isDark
                                    ? Colors.black.withValues(alpha: 0.3)
                                    : Colors.white,
                                child: Stack(
                                  children: [
                                    const ModelViewer(
                                      key: ValueKey('ambulance_3d_inspector'),
                                      src: 'assets/3d_models/ambulance.glb',
                                      alt: '3D Emergency Ambulance Unit',
                                      ar: false,
                                      autoRotate: true,
                                      autoRotateDelay: 0,
                                      rotationPerSecond: '30deg',
                                      cameraControls: true,
                                      backgroundColor: Colors.transparent,
                                    ),
                                    Positioned(
                                      bottom: 6,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.touch_app, size: 10, color: Colors.white70),
                                            SizedBox(width: 4),
                                            Text(
                                              'Drag to rotate 360°',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Hospital & Crew Details Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.local_hospital,
                                    color: Color(0xFF4CAF50), size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.booking.hospitalName,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? AppTheme.darkTextLight
                                            : AppTheme.textDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${widget.booking.vehicleNumber} • ${widget.booking.paramedicName}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? AppTheme.darkTextDim
                                            : AppTheme.textGray,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.sensors, size: 13, color: Color(0xFFFF3B30)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Alert: ${widget.booking.criticalAlert}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFF3B30),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Action Buttons: Call Dispatch & Cancel Ambulance
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.phone_in_talk, size: 17),
                            label: const Text(
                              'Call Dispatch (108)',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: () => _makeCall(widget.booking.driverPhone),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF3B30),
                            side: const BorderSide(color: Color(0xFFFF3B30)),
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _confirmCancel,
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Top-View realistic ambulance marker with directional dual headlights
  Widget _buildTopViewAmbulanceMarker() {
    return AnimatedBuilder(
      animation: _pulseAnimCtrl,
      builder: (context, _) {
        return Transform.rotate(
          angle: _currentBearing,
          alignment: Alignment.center,
          child: SizedBox(
            width: 72,
            height: 96,
            child: CustomPaint(
              painter: AmbulanceTopViewPainter(
                strobePhase: _pulseAnimCtrl.value,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 3D Model map marker viewing ambulance.glb from top-down angle
  Widget _build3DMapMarker() {
    return Transform.rotate(
      angle: _currentBearing,
      alignment: Alignment.center,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.15),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.35),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(
          child: const ModelViewer(
            key: ValueKey('ambulance_map_marker_3d'),
            src: 'assets/3d_models/ambulance.glb',
            alt: '3D Ambulance',
            ar: false,
            autoRotate: false,
            cameraControls: false,
            cameraOrbit: '0deg 30deg 105%',
            backgroundColor: Colors.transparent,
          ),
        ),
      ),
    );
  }

  Widget _buildMapActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required bool isDark,
    bool active = false,
    Color activeColor = const Color(0xFFFF3B30),
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: active
                  ? activeColor
                  : (isDark ? const Color(0xFF1E293B) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? Colors.white38
                    : (isDark ? Colors.white12 : Colors.black12),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 20,
              color: active
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  void _open3DAmbulanceFullScreenModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 30,
                    offset: Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Top bar with drag handle and close button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.view_in_ar_rounded,
                              color: Color(0xFFFF3B30), size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '3D ALS Ambulance • ${widget.booking.vehicleNumber}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              Text(
                                'Advanced Life Support ICU Vehicle Inspector',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 24),
                          color: isDark ? Colors.white70 : Colors.black54,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),

                  // Large interactive 3D model viewer
                  Expanded(
                    child: Stack(
                      children: [
                        const ModelViewer(
                          key: ValueKey('ambulance_3d_fullscreen'),
                          src: 'assets/3d_models/ambulance.glb',
                          alt: '3D ALS Emergency Ambulance',
                          ar: false,
                          autoRotate: true,
                          autoRotateDelay: 0,
                          rotationPerSecond: '25deg',
                          cameraControls: true,
                          backgroundColor: Colors.transparent,
                        ),
                        Positioned(
                          top: 12,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.touch_app_rounded, color: Colors.white70, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'Interactive 360° • Pinch to Zoom • Drag to Orbit',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Equipment & Telemetry specs
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.medical_services_outlined, size: 16, color: Color(0xFF10B981)),
                            SizedBox(width: 6),
                            Text(
                              'Onboard ICU Clinical Telemetry',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            _EquipmentPill(icon: Icons.air, label: 'Hamilton-T1 Transport Ventilator'),
                            _EquipmentPill(icon: Icons.monitor_heart, label: 'Zoll X-Series Monitor / Defib'),
                            _EquipmentPill(icon: Icons.vaccines, label: 'B. Braun Syringe Infusion Pump'),
                            _EquipmentPill(icon: Icons.local_gas_station, label: 'O2 Tank: 15L @ 200 bar'),
                            _EquipmentPill(icon: Icons.groups, label: 'ALS Paramedic Crew: Dispatched'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Custom painter for top-view emergency vehicle with forward headlight illumination
class AmbulanceTopViewPainter extends CustomPainter {
  final double strobePhase;

  AmbulanceTopViewPainter({required this.strobePhase});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    // Vehicle center is at Y = 54, front at Y = 28, rear at Y = 80
    // Headlights shine upward (from Y=28 to Y=0)

    final leftHeadlight = Offset(centerX - 8.5, 28);
    final rightHeadlight = Offset(centerX + 8.5, 28);

    // 1. Dual Glowing Headlight Beam Cones (projecting forward onto road)
    final beamPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(centerX, 28),
        Offset(centerX, 0),
        [
          Colors.yellowAccent.withValues(alpha: 0.65),
          Colors.white.withValues(alpha: 0.40),
          Colors.white.withValues(alpha: 0.0),
        ],
        [0.0, 0.45, 1.0],
      )
      ..style = PaintingStyle.fill;

    // Left forward beam cone
    final leftBeam = Path()
      ..moveTo(leftHeadlight.dx, leftHeadlight.dy)
      ..lineTo(leftHeadlight.dx - 16, 0)
      ..lineTo(leftHeadlight.dx + 5, 0)
      ..close();
    canvas.drawPath(leftBeam, beamPaint);

    // Right forward beam cone
    final rightBeam = Path()
      ..moveTo(rightHeadlight.dx, rightHeadlight.dy)
      ..lineTo(rightHeadlight.dx - 5, 0)
      ..lineTo(rightHeadlight.dx + 16, 0)
      ..close();
    canvas.drawPath(rightBeam, beamPaint);

    // 2. Vehicle Drop Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final shadowRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(centerX, 55), width: 28, height: 54),
      const Radius.circular(8),
    );
    canvas.drawRRect(shadowRect, shadowPaint);

    // 3. Ambulance Chassis (Clean Medical White Body)
    final bodyPaint = Paint()..color = Colors.white;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(centerX, 54), width: 26, height: 52),
      const Radius.circular(7),
    );
    canvas.drawRRect(bodyRect, bodyPaint);

    // Chassis Subtle Border
    final outlinePaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(bodyRect, outlinePaint);

    // 4. Side Emergency Red Racing Stripes
    final stripePaint = Paint()..color = const Color(0xFFFF3B30);
    canvas.drawRect(Rect.fromLTWH(centerX - 13, 38, 2.5, 30), stripePaint);
    canvas.drawRect(Rect.fromLTWH(centerX + 10.5, 38, 2.5, 30), stripePaint);

    // 5. Front Windshield (Dark Tinted Curved Glass)
    final glassPaint = Paint()..color = const Color(0xFF1E293B);
    final glassRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(centerX, 36), width: 20, height: 7),
      const Radius.circular(3),
    );
    canvas.drawRRect(glassRect, glassPaint);

    // Windshield Glass Highlight
    final glassReflect = Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(centerX - 6, 35), Offset(centerX - 2, 37), glassReflect);

    // 6. Medical Red Cross on Roof
    final crossPaint = Paint()..color = const Color(0xFFFF3B30);
    // Vertical bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(centerX, 60), width: 4.5, height: 14),
        const Radius.circular(1),
      ),
      crossPaint,
    );
    // Horizontal bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(centerX, 60), width: 14, height: 4.5),
        const Radius.circular(1),
      ),
      crossPaint,
    );

    // 7. Roof Emergency Strobe Lightbar
    final lightbarHousing = Paint()..color = const Color(0xFF334155);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(centerX, 45), width: 18, height: 4.5),
        const Radius.circular(1.5),
      ),
      lightbarHousing,
    );

    // Alternating Dual-Phase Strobe LEDs (Red / Blue)
    final isPhaseA = strobePhase < 0.5;
    final redStrobe = Paint()
      ..color = isPhaseA ? const Color(0xFFFF1744) : const Color(0xFF880E4F)
      ..maskFilter = isPhaseA ? const MaskFilter.blur(BlurStyle.solid, 4) : null;
    final blueStrobe = Paint()
      ..color = !isPhaseA ? const Color(0xFF00E5FF) : const Color(0xFF0D47A1)
      ..maskFilter = !isPhaseA ? const MaskFilter.blur(BlurStyle.solid, 4) : null;

    canvas.drawCircle(Offset(centerX - 5, 45), 2.8, redStrobe);
    canvas.drawCircle(Offset(centerX + 5, 45), 2.8, blueStrobe);

    // 8. Headlight Bulbs (High-intensity white LEDs at front corners)
    final bulbPaint = Paint()..color = Colors.white;
    canvas.drawCircle(leftHeadlight, 2.0, bulbPaint);
    canvas.drawCircle(rightHeadlight, 2.0, bulbPaint);

    // 9. Rear Tail Lights (Red Braking LEDs)
    final tailPaint = Paint()..color = const Color(0xFFFF3B30);
    canvas.drawCircle(Offset(centerX - 9, 78), 1.8, tailPaint);
    canvas.drawCircle(Offset(centerX + 9, 78), 1.8, tailPaint);
  }

  @override
  bool shouldRepaint(covariant AmbulanceTopViewPainter oldDelegate) {
    return oldDelegate.strobePhase != strobePhase;
  }
}

class _EquipmentPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EquipmentPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF10B981)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}
