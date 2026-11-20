import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ARService {
  /// Base GitHub URL hosting the verified, CORS-enabled 3D GLB models
  static const String _remoteModelBaseUrl =
      'https://raw.githubusercontent.com/atharva-awade/Team-Synora-MedicoScope-AI-Powered-Clinic-in-you-Pocket/main/assets/3d_models';

  /// Get the verified public HTTPS URL for any 3D model asset
  static String getHttpsModelUrl(String modelPath) {
    final fileName = modelPath.split('/').last;
    return '$_remoteModelBaseUrl/$fileName';
  }

  /// Launch AR viewer for the given 3D model
  /// On iOS: Uses AR Quick Look with USDZ / GLB files
  /// On Android: Uses Google Scene Viewer / WebXR with verified HTTPS URL
  static Future<bool> launchARViewer(String modelPath, {String? title}) async {
    try {
      if (Platform.isIOS) {
        return await _launchIOSARQuickLook(modelPath);
      } else if (Platform.isAndroid) {
        return await _launchAndroidSceneViewer(modelPath, title: title);
      } else {
        print('AR viewing is not supported on this platform');
        return false;
      }
    } catch (e) {
      print('Error launching AR viewer: $e');
      return false;
    }
  }

  /// Launch AR Quick Look on iOS
  static Future<bool> _launchIOSARQuickLook(String modelPath) async {
    try {
      final ByteData data = await rootBundle.load(modelPath);
      final List<int> bytes = data.buffer.asUint8List();

      final Directory tempDir = await getTemporaryDirectory();
      final String fileName = modelPath.split('/').last;
      final File tempFile = File('${tempDir.path}/$fileName');

      await tempFile.writeAsBytes(bytes);

      final Uri arUrl = Uri.parse('file://${tempFile.path}');

      if (await canLaunchUrl(arUrl)) {
        return await launchUrl(
          arUrl,
          mode: LaunchMode.externalApplication,
        );
      } else {
        print('Cannot launch AR Quick Look');
        return false;
      }
    } catch (e) {
      print('Error launching iOS AR Quick Look: $e');
      return false;
    }
  }

  /// Launch Google AR / Scene Viewer on Android
  static Future<bool> _launchAndroidSceneViewer(
    String modelPath, {
    String? title,
  }) async {
    try {
      final String fileName = modelPath.split('/').last;
      final String resolvedTitle = (title != null && title.isNotEmpty)
          ? title
          : fileName
              .replaceAll('.glb', '')
              .replaceAll('-', ' ')
              .split(' ')
              .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
              .join(' ');

      // Google Scene Viewer strictly requires an HTTPS URL from a CORS-enabled server
      final String httpsModelUrl = getHttpsModelUrl(modelPath);

      // Extract asset bytes to a temporary file as secondary fallback
      File? localFile;
      try {
        final ByteData data = await rootBundle.load(modelPath);
        final List<int> bytes = data.buffer.asUint8List();
        final Directory tempDir = await getTemporaryDirectory();
        localFile = File('${tempDir.path}/$fileName');
        await localFile.writeAsBytes(bytes, flush: true);
      } catch (e) {
        print('Error extracting asset for Scene Viewer fallback: $e');
      }

      const platform = MethodChannel('com.example.medicoscope/ar');

      // 1. Native Scene Viewer Intent via ARCore / Google App / Chrome
      try {
        final bool? success = await platform.invokeMethod<bool>(
          'launchSceneViewer',
          {
            if (localFile != null && await localFile.exists())
              'filePath': localFile.path,
            'modelUrl': httpsModelUrl,
            'title': resolvedTitle,
          },
        );
        if (success == true) {
          return true;
        }
      } catch (e) {
        print('Native launchSceneViewer failed: $e, falling back to url_launcher');
      }

      // 2. Intent URL fallback via url_launcher
      final String encodedTitle = Uri.encodeComponent(resolvedTitle);
      final String encodedModelUrl = Uri.encodeComponent(httpsModelUrl);
      final Uri sceneViewerUrl = Uri.parse(
        'intent://arvr.google.com/scene-viewer/1.0?file=$encodedModelUrl&mode=ar_preferred&title=$encodedTitle&resizable=true#Intent;scheme=https;package=com.google.android.googlequicksearchbox;action=android.intent.action.VIEW;S.browser_fallback_url=https%3A%2F%2Fdevelopers.google.com%2Far;end;',
      );

      try {
        if (await canLaunchUrl(sceneViewerUrl)) {
          return await launchUrl(
            sceneViewerUrl,
            mode: LaunchMode.externalNonBrowserApplication,
          );
        }
      } catch (_) {}

      // 3. Fallback to generic system external application
      try {
        final Uri directViewerUri = Uri.parse(
          'https://arvr.google.com/scene-viewer/1.0?file=$encodedModelUrl&mode=ar_preferred&title=$encodedTitle&resizable=true',
        );
        return await launchUrl(
          directViewerUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        print('Direct Scene Viewer link failed: $e');
        return false;
      }
    } catch (e) {
      print('Error launching Android Scene Viewer: $e');
      return false;
    }
  }

  /// Check if AR is supported on the current device
  static bool isARSupported() {
    return Platform.isIOS || Platform.isAndroid;
  }

  /// Get a user-friendly message about AR support
  static String getARSupportMessage() {
    if (Platform.isIOS) {
      return 'AR viewing requires iOS 12 or later';
    } else if (Platform.isAndroid) {
      return 'AR viewing requires Google Play Services for AR (ARCore)';
    } else {
      return 'AR viewing is not supported on this platform';
    }
  }
}
