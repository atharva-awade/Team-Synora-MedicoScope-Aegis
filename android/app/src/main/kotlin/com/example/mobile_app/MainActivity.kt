package com.example.mobile_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Using FlutterFragmentActivity instead of FlutterActivity because the
 * health package's Health Connect permission launcher (ActivityResultLauncher)
 * must be registered during onCreate(), which requires Fragment support.
 */
class MainActivity : FlutterFragmentActivity() {
    private val AR_CHANNEL = "com.example.medicoscope/ar"
    private val SMS_CHANNEL = "medicoscope/native_sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Native SMS Channel for background SOS dispatch
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sendDirectSms") {
                val phone = call.argument<String>("phone")
                val message = call.argument<String>("message")
                if (phone.isNullOrBlank() || message.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "Phone and message required", null)
                    return@setMethodCallHandler
                }
                try {
                    val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        applicationContext.getSystemService(SmsManager::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getDefault()
                    }
                    val parts = smsManager.divideMessage(message)
                    smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SMS_FAILED", e.localizedMessage ?: "Failed to send background SMS", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // Native AR Channel for Scene Viewer and FileProvider
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getContentUri" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val file = File(filePath)
                            val uri = FileProvider.getUriForFile(
                                this,
                                "${applicationContext.packageName}.fileprovider",
                                file
                            )
                            result.success(uri.toString())
                        } catch (e: Exception) {
                            result.error("FILE_PROVIDER_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "File path cannot be null", null)
                    }
                }
                "launchSceneViewer" -> {
                    val filePath = call.argument<String>("filePath")
                    val modelUrl = call.argument<String>("modelUrl")
                    val title = call.argument<String>("title") ?: "3D Model"

                    try {
                        val remoteUrl = if (!modelUrl.isNullOrBlank()) modelUrl else null
                        var launched = false

                        // 1. Try Google Play Services for AR (ARCore native forwarder)
                        if (!remoteUrl.isNullOrBlank()) {
                            val sceneViewerUri = Uri.parse("https://arvr.google.com/scene-viewer/1.0").buildUpon()
                                .appendQueryParameter("file", remoteUrl)
                                .appendQueryParameter("mode", "ar_preferred")
                                .appendQueryParameter("title", title)
                                .appendQueryParameter("resizable", "true")
                                .build()

                            // Tier 1: Target com.google.ar.core directly
                            try {
                                val arCoreIntent = Intent(Intent.ACTION_VIEW, sceneViewerUri).apply {
                                    setPackage("com.google.ar.core")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                if (arCoreIntent.resolveActivity(packageManager) != null) {
                                    startActivity(arCoreIntent)
                                    launched = true
                                    android.util.Log.i("MainActivity", "Launched Scene Viewer via com.google.ar.core")
                                }
                            } catch (e: Exception) {
                                android.util.Log.w("MainActivity", "ARCore Scene Viewer failed: ${e.message}")
                            }

                            // Tier 2: Try Google QuickSearchBox explicit package (Google App)
                            if (!launched) {
                                try {
                                    val gsbIntent = Intent(Intent.ACTION_VIEW, sceneViewerUri).apply {
                                        setPackage("com.google.android.googlequicksearchbox")
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    if (gsbIntent.resolveActivity(packageManager) != null) {
                                        startActivity(gsbIntent)
                                        launched = true
                                        android.util.Log.i("MainActivity", "Launched Scene Viewer via com.google.android.googlequicksearchbox")
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.w("MainActivity", "QSB Scene Viewer failed: ${e.message}")
                                }
                            }

                            // Tier 3: Fallback to Google Chrome browser / WebXR AR renderer
                            if (!launched) {
                                try {
                                    val chromeIntent = Intent(Intent.ACTION_VIEW, sceneViewerUri).apply {
                                        setPackage("com.android.chrome")
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    if (chromeIntent.resolveActivity(packageManager) != null) {
                                        startActivity(chromeIntent)
                                        launched = true
                                        android.util.Log.i("MainActivity", "Launched Scene Viewer via com.android.chrome")
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.w("MainActivity", "Chrome Scene Viewer failed: ${e.message}")
                                }
                            }

                            // Tier 4: Fallback to generic system handler
                            if (!launched) {
                                try {
                                    val genericIntent = Intent(Intent.ACTION_VIEW, sceneViewerUri).apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(genericIntent)
                                    launched = true
                                    android.util.Log.i("MainActivity", "Launched Scene Viewer via generic system handler")
                                } catch (e: Exception) {
                                    android.util.Log.w("MainActivity", "Generic Scene Viewer failed: ${e.message}")
                                }
                            }
                        }

                        // 5. Local FileProvider fallback if remote launch did not succeed
                        if (!launched && !filePath.isNullOrBlank()) {
                            val file = File(filePath)
                            if (file.exists()) {
                                val contentUri = FileProvider.getUriForFile(
                                    this,
                                    "${applicationContext.packageName}.fileprovider",
                                    file
                                )
                                try {
                                    grantUriPermission("com.google.android.googlequicksearchbox", contentUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    grantUriPermission("com.google.ar.core", contentUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    grantUriPermission("com.android.chrome", contentUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                } catch (_: Exception) {}

                                try {
                                    val fileIntent = Intent(Intent.ACTION_VIEW).apply {
                                        setDataAndType(contentUri, "model/gltf-binary")
                                        setPackage("com.google.android.googlequicksearchbox")
                                        putExtra("mode", "ar_preferred")
                                        putExtra("title", title)
                                        putExtra("resizable", true)
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(fileIntent)
                                    launched = true
                                } catch (e: Exception) {
                                    android.util.Log.w("MainActivity", "FileProvider QSB Scene Viewer failed: ${e.message}")
                                }

                                if (!launched) {
                                    try {
                                        val genericFileIntent = Intent(Intent.ACTION_VIEW).apply {
                                            setDataAndType(contentUri, "model/gltf-binary")
                                            putExtra("mode", "ar_preferred")
                                            putExtra("title", title)
                                            putExtra("resizable", true)
                                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                        }
                                        startActivity(genericFileIntent)
                                        launched = true
                                    } catch (e: Exception) {
                                        android.util.Log.w("MainActivity", "Generic FileProvider Scene Viewer failed: ${e.message}")
                                    }
                                }
                            }
                        }

                        if (launched) {
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                        return@setMethodCallHandler
                    } catch (e: Exception) {
                        result.error("LAUNCH_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
