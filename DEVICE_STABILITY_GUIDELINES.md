# Device Stability & Physical Safety Guidelines
**MedicoScope Mobile Engineering Rulebook**

This document establishes mandatory, permanent safety guardrails to ensure that development, testing, and deployment processes never stress the connected physical device, cause operating system freezing, or overload memory.

---

## 1. 3D Model & AR Lifecycle Management
1. **Unmount Native WebGL Views During Transitions**:
   - The embedded `ModelViewer` (Android WebView / WebGL canvas) must be conditionally unmounted whenever the app transitions to the background or launches an external AR Activity (`Scene Viewer`).
   - Never allow simultaneous WebGL contexts between the Flutter embedding window and external Scene Viewer.
2. **Prevent Duplicate In-Canvas AR Buttons**:
   - Always enforce `ar: false` on the embedded `<model-viewer>` component.
   - External AR sessions must only be launched via the application's native `ARService` and `MainActivity.kt` 4-tier dispatch pipeline (`com.google.android.googlequicksearchbox` / `com.android.chrome` / `ACTION_VIEW` / `FileProvider`), never through `model_viewer_plus`'s local proxy port (`127.0.0.1`).
3. **Hardware Surface Recreation Grace Period**:
   - Android requires 500–800 ms to rebuild OpenGL hardware window surfaces upon returning from an external activity.
   - Always enforce an 800 ms stabilization delay in `didChangeAppLifecycleState(AppLifecycleState.resumed)` before remounting embedded 3D views.

---

## 2. ADB & USB Session Safety
1. **No Hot-Looping or Unbounded Polling**:
   - Automated scripts must never poll ADB or issue repetitive commands in sub-second intervals.
   - All ADB calls must specify strict timeouts (3–5 seconds maximum) and use `stdin=subprocess.DEVNULL` to avoid keeping open interactive terminal handles.
2. **Clean Process Management**:
   - Before executing builds or installations, ensure only a single ADB daemon is active. Never allow orphaned ADB client processes to hold USB transport locks.
3. **Respect Power States**:
   - Never issue wake/input loops when a device is in sleep or bypass-charging mode.

---

## 3. Graceful Error Handling
- Every external hardware or platform intent call must be wrapped in defensive `try-catch` blocks.
- If an AR intent fails or Google Play Services for AR is unavailable, the UI must immediately restore the user to the 3D inspection view with a clear, non-blocking notification, rather than retrying.
