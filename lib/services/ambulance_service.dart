import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:medicoscope/models/ambulance_booking_model.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:medicoscope/services/location_service.dart';
import 'package:medicoscope/services/overpass_hospitals_service.dart';
import 'package:medicoscope/widgets/critical_alert_countdown_dialog.dart';
import 'package:medicoscope/main.dart';
import 'package:medicoscope/screens/ambulance/ambulance_tracking_screen.dart';

class AmbulanceService {
  static AmbulanceBooking? _currentActiveBooking;
  static bool _isCountdownShowing = false;

  static AmbulanceBooking? get currentBooking => _currentActiveBooking;

  /// Trigger the countdown popup for any critical alert across the app.
  static void triggerCriticalAlertCountdown({
    required BuildContext context,
    required String alertHeadline,
    required String alertSeverity,
    required String patientName,
    String? patientId,
    String? details,
    int countdownSeconds = 5,
  }) {
    if (_isCountdownShowing) return;
    _isCountdownShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CriticalAlertCountdownDialog(
        alertHeadline: alertHeadline,
        alertSeverity: alertSeverity,
        patientName: patientName,
        countdownSeconds: countdownSeconds,
        onConfirmed: () async {
          _isCountdownShowing = false;
          Navigator.of(ctx).pop();
          // Book ambulance and navigate to tracking simulation
          final booking = await bookEmergencyAmbulance(
            patientName: patientName,
            patientId: patientId ?? 'anonymous',
            criticalAlert: '$alertHeadline ${details ?? ''}',
          );
          final targetCtx = appNavigatorKey.currentContext ?? context;
          if (targetCtx.mounted) {
            Navigator.of(targetCtx).push(
              MaterialPageRoute(
                builder: (_) => AmbulanceTrackingScreen(booking: booking),
              ),
            );
          }
        },
        onCancelled: () {
          _isCountdownShowing = false;
          Navigator.of(ctx).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ambulance auto-booking cancelled by user.'),
              backgroundColor: Colors.blueGrey,
            ),
          );
        },
      ),
    ).then((_) => _isCountdownShowing = false);
  }

  /// Finds the closest medical facility and creates an active ambulance booking.
  static Future<AmbulanceBooking> bookEmergencyAmbulance({
    required String patientName,
    required String patientId,
    required String criticalAlert,
  }) async {
    final fix = await LocationService.getFix();
    final patientLat = fix.latitude ?? 28.6139; // Default fallback to city coordinates if GPS disabled
    final patientLng = fix.longitude ?? 77.2090;

    String hospitalName = 'City Emergency Trauma Center';
    double hospLat = patientLat + 0.018; // ~2km offset
    double hospLng = patientLng + 0.015;
    int etaMinutes = 7;

    try {
      final hospitals = await OverpassHospitalsService.fetchNearby(
        center: LatLng(patientLat, patientLng),
        radiusMeters: 5000,
      ).timeout(const Duration(seconds: 4), onTimeout: () => []);

      if (hospitals.isNotEmpty) {
        final nearest = hospitals.first;
        hospitalName = nearest.name;
        hospLat = nearest.location.latitude;
        hospLng = nearest.location.longitude;
        final distKm = nearest.distanceMeters / 1000.0;
        etaMinutes = math.max(3, (distKm * 2.5).round());
      }
    } catch (_) {}

    final bookingPayload = {
      'bookingId': 'AMB-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      'patientId': patientId,
      'patientName': patientName,
      'hospitalName': hospitalName,
      'hospitalLocation': {
        'latitude': hospLat,
        'longitude': hospLng,
      },
      'patientLocation': {
        'latitude': patientLat,
        'longitude': patientLng,
      },
      'paramedicName': 'Dr. Sharma & ALS ICU Paramedic Crew',
      'driverPhone': '108',
      'vehicleNumber': 'MED-ALS-${(100 + math.Random().nextInt(899))}',
      'etaMinutes': etaMinutes,
      'status': 'dispatched',
      'criticalAlert': criticalAlert,
      'dispatchedAt': DateTime.now().toIso8601String(),
    };

    final booking = AmbulanceBooking.fromJson(bookingPayload);
    _currentActiveBooking = booking;

    // Post to backend (best-effort)
    try {
      final api = ApiService();
      await api.post('/ambulance/book', bookingPayload);
    } catch (_) {}

    return booking;
  }

  /// Calculates the mathematical bearing in radians from True North (clockwise).
  static double calculateBearing(LatLng from, LatLng to) {
    final phi1 = from.latitude * (math.pi / 180.0);
    final phi2 = to.latitude * (math.pi / 180.0);
    final deltaLambda = (to.longitude - from.longitude) * (math.pi / 180.0);
    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    return math.atan2(y, x);
  }

  /// Interpolates a smooth, realistic road polyline from hospital to user coordinates.
  /// Eliminates erratic jitter and mimics real street corridors with smooth elbows.
  static List<LatLng> generateRouteCoordinates({
    required LatLng start,
    required LatLng end,
    int steps = 60,
  }) {
    if (steps < 2) return [start, end];

    final dLat = end.latitude - start.latitude;
    final dLng = end.longitude - start.longitude;

    // Realistic road corridor elbows resembling street grid turns
    final w1 = LatLng(
      start.latitude + (dLat * 0.35) + (dLng * 0.12),
      start.longitude + (dLng * 0.25) - (dLat * 0.08),
    );
    final w2 = LatLng(
      start.latitude + (dLat * 0.68) - (dLng * 0.08),
      start.longitude + (dLng * 0.72) + (dLat * 0.10),
    );

    final anchors = [start, w1, w2, end];
    final points = <LatLng>[start];

    final seg1Steps = steps ~/ 3;
    final seg2Steps = steps ~/ 3;
    final seg3Steps = steps - seg1Steps - seg2Steps;
    final segStepCounts = [seg1Steps, seg2Steps, seg3Steps];

    for (int i = 0; i < 3; i++) {
      final pA = anchors[i];
      final pB = anchors[i + 1];
      final count = segStepCounts[i];
      for (int s = 1; s <= count; s++) {
        final t = s / count;
        if (i == 2 && s == count) {
          points.add(end);
        } else {
          points.add(
            LatLng(
              pA.latitude + (pB.latitude - pA.latitude) * t,
              pA.longitude + (pB.longitude - pA.longitude) * t,
            ),
          );
        }
      }
    }

    return points;
  }
}
