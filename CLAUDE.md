# Quick Camera - Project Context for AI Assistants

## Project Overview

Quick Camera is a macOS utility application that displays output from USB-based cameras on the desktop. It's primarily used for presentations where users need to show external device output to an audience. The app is available on the Mac App Store.

**Key Features:**
- Display any USB camera feed in a resizable window
- Mirror (horizontal and vertical flip)
- Rotate in 90° increments
- Borderless mode with always-on-top
- Aspect ratio locking
- Capture snapshots as PNG, saved silently to a folder you choose once
- Hands-free capture by saying "snap" (opt-in, on-device speech recognition)
- Hot-plug camera detection (USB and Continuity Camera)
- Persistent window position and settings

## Technical Stack

- **Platform**: macOS 26.6+ (deployment target)
- **Language**: Swift 5 language mode
- **UI Framework**: AppKit (traditional NSApplication, not SwiftUI)
- **Build System**: Xcode project (`Quick Camera.xcodeproj`)
- **Key Frameworks**:
  - AVFoundation (camera capture, device discovery, microphone capture)
  - Speech (on-device transcription for the "snap" voice command)
  - CoreImage (converting captured frames to images)
  - Cocoa/AppKit (UI)
  - os (unified logging)

## Architecture

### File Structure

App target (`Quick Camera/`):

1. **QCAppDelegate.swift**
   - Main application controller; `@main` and `@MainActor`-isolated
   - Manages camera capture sessions and the preview layer
   - Handles all UI interactions via IBOutlets and IBActions
   - Coordinates settings, device watching, and snapshot capture

2. **QCSettingsManager.swift**
   - Singleton (`shared`) for settings, `@MainActor`-isolated
   - Persists user preferences via UserDefaults
   - Manages: device name, mirror states, rotation, window frame, borderless mode, snapshots folder bookmark, voice command toggle

3. **QCUsbWatcher.swift**
   - Notifies the delegate when the set of video devices changes
   - Key-value observes `AVCaptureDevice.DiscoverySession.devices` (no IOKit)

4. **QCRotation.swift**
   - Pure rotation maths (angle, landscape check, stepping)
   - Deliberately free of session/window state so it can be unit tested

5. **QCSnapshotFile.swift**
   - Snapshot filename generation and filename-collision handling
   - Time zone/locale/calendar are parameters so naming is testable

6. **QCVoiceCommand.swift**
   - Pure trigger-word matching and cooldown logic for the voice command
   - Deliberately free of audio/session state so it can be unit tested

7. **QCVoiceListener.swift**
   - Listens to the microphone via its own `AVAudioEngine` and transcribes on-device with `SpeechAnalyzer`/`SpeechTranscriber`
   - Reports trigger matches and failures through `QCVoiceListenerDelegate`

Test target (`Quick Camera Tests/`) — uses **Swift Testing**, not XCTest:

- **QCRotationTests.swift**, **QCSnapshotFileTests.swift**, **QCSettingsManagerTests.swift**, **QCVoiceCommandTests.swift**

### Key Design Patterns

- **Singleton**: `QCSettingsManager.shared` for centralized settings
- **Delegate**: `QCUsbWatcherDelegate` for device-change notifications
- **Interface Builder**: XIB with `@IBOutlet` and `@IBAction`
- **MVC**: Traditional Model-View-Controller architecture

## Important Implementation Details

### Concurrency

- `QCAppDelegate`, `QCSettingsManager` and `QCUsbWatcher` are all `@MainActor`-isolated.
- `captureOutput(_:didOutput:from:)` is explicitly `nonisolated` — it runs on `videoDataQueue`, which also serialises access to `latestFrame` (declared `nonisolated(unsafe)` for that reason).
- `AVCaptureSession.startRunning()`/`stopRunning()` block, so they run on a serial `sessionQueue` (GCD). **Do not convert these to `Task`** — AVCaptureSession has no async API and Apple's guidance is a dedicated serial queue.
- AVFoundation is imported with `@preconcurrency` because it predates Sendable annotations.
- Everywhere else, prefer async/await over completion handlers (e.g. `await panel.begin()`, `await AVCaptureDevice.requestAccess(for:)`).

### Camera Management

- Uses `AVCaptureDevice.DiscoverySession` to enumerate devices
- Device types: `.builtInWideAngleCamera` plus `.external`
- Camera permission is requested explicitly with `AVCaptureDevice.requestAccess(for: .video)`; denial shows an alert and terminates
- Device menu updates automatically when devices connect/disconnect
- Keyboard shortcuts 1-9 for quick camera switching
- Prevents unnecessary session restarts when selecting the already-active device

### Display Transformations

- **Rotation**: 4 positions (0-3) representing 0°, 90°, 180°, 270°
- **Position 0**: Portrait, 1: Landscape Left, 2: Portrait Upside Down, 3: Landscape Right
- All maths lives in `QCRotation`; rotation combines with the vertical flip (adds 180°)
- Rotation is applied by setting `AVCaptureConnection.videoRotationAngle`
- Transformations are applied to **both** the preview connection and the video-data-output connection (see `videoConnections`), so saved images match the screen
- Window dimensions swap when rotating 90°/270°

### Window Behavior

- **Borderless mode**: Removes title bar, makes window always-on-top (maximum window level), enables drag-by-background
- **Aspect ratio**: Can be locked to match camera's native resolution
- **Full screen**: Standard macOS full screen support
- **Frame persistence**: Saved as `windowFrame`; frames with width or height ≤ 100 are treated as unusable and ignored

### Image Capture

- An `AVCaptureVideoDataOutput` keeps the most recent frame in `latestFrame`
- Saving converts that frame via a cached `CIContext` (creating one per capture is expensive) and writes PNG with `CGImageDestination`
- Snapshots save **silently** to a user-chosen folder; the folder is remembered via a **security-scoped bookmark** (required by the sandbox) and persists immediately, without "Save Settings"
- Filename format: `Quick Camera Image YYYY-MM-DD at h.mm.ss a.png`, built with `Date.VerbatimFormatStyle`
- Timestamps only have one-second resolution, so `QCSnapshotFile.uniqueURL` appends ` 2`, ` 3`, … rather than overwriting
- A brief white flash over the preview confirms the capture. **Do not use `NSSound` for this** — it trips a sandbox mach-lookup denial for `com.apple.audioanalyticsd`

### Voice Command ("snap")

- Opt-in via the programmatically inserted "Listen for “Snap”" menu item; the `voiceCommandEnabled` setting persists immediately (like the snapshots folder) and listening resumes on the next launch
- `QCVoiceListener` transcribes the mic fully on-device: `SpeechTranscriber` with the `.progressiveTranscription` preset (volatile + fast results) feeding a `SpeechAnalyzer`
- **`CaptureInputSequenceProvider` is macOS 27+ only** — on this deployment target (26.6), mic audio comes from an `AVAudioEngine` input tap, converted to the analyzer's format with `AVAudioConverter` and yielded as `AnalyzerInput` buffers through an `AsyncStream`
- The mic gets its own audio engine; the camera `AVCaptureSession` is untouched
- Matching lives in `QCVoiceCommand`: whole-word match only ("snapshot"/"snapped" don't fire) plus a 3s cooldown, because live transcription reports the same utterance several times (volatile refinements then the finalized text)
- Requires the `com.apple.security.device.audio-input` entitlement and `NSMicrophoneUsageDescription`; mic permission is requested with `AVCaptureDevice.requestAccess(for: .audio)`. The new SpeechAnalyzer API does **not** need the old speech-recognition authorization
- First enable downloads the transcription model via `AssetInventory` (needs network once; a no-op afterwards)
- A recognized trigger calls the same `captureSnapshot()` as the menu item, so the white flash doubles as confirmation

### Device Monitoring

- `QCUsbWatcher` KVOs `DiscoverySession.devices`; AVFoundation only publishes devices once they are ready, so no settle delay is needed
- KVO can fire on any thread, so the delegate call hops via `Task { @MainActor in … }`

## Code Style & Conventions

- Uses `// MARK: -` comments extensively to organize code sections
- `QCAppDelegate` exposes computed properties that forward to `QCSettingsManager.shared`
- Logging via `os.Logger` (subsystem `com.jasonkristian.QCamera`), **not** `NSLog`; user-facing strings and paths are marked `privacy: .public` to stay readable in Console
- Error handling via NSAlert modal dialogs
- Comments explain non-obvious constraints (sandbox limits, blocking APIs), not what the code does

## Testing

- Framework: **Swift Testing** (`@Test`, `@Suite`, `#expect`) — not XCTest
- Run with the `RunAllTests` tool, or `xcodebuild test -scheme "Quick Camera"`
- Tests are hosted in the app. `QCAppDelegate.isRunningTests` detects the XCTest environment and **skips camera startup**, so test runs don't turn the camera light on
- `QCSettingsManager` has an `init(defaults:domain:)` test seam; tests use a throwaway `UserDefaults` suite so the real preferences (including the snapshots folder) are never touched
- Prefer extending `QCRotation`/`QCSnapshotFile`/`QCVoiceCommand` for new logic that deserves coverage, rather than burying it in the app delegate
- The scheme is shared (`xcshareddata/xcschemes/Quick Camera.xcscheme`) and includes the test target

## Build & Distribution

- Primary build: Xcode with `Quick Camera.xcodeproj`
- Command line: `xcodebuild -scheme Quick\ Camera -configuration Release clean build`
- App Store distribution via Mac App Store
- Sandboxed: entitlements grant camera access, microphone access (voice command), and user-selected read/write files

## Known Considerations

1. **Interface Builder**: UI is defined in `MainMenu.xib`; the "Set Snapshots Folder…" and "Listen for “Snap”" items are inserted programmatically at launch (`addSnapshotMenuItems()`) to avoid hand-editing the XIB
2. **Implicitly unwrapped optionals**: `captureSession`, `input`, `devices`, `captureLayer`, `videoOutput` are still IUOs — a known cleanup opportunity, deliberately deferred
3. **Hardware camera buttons**: UVC "snap" buttons cannot be detected on macOS — Apple's UVC driver owns the control interface and never enables hardware-trigger mode. Don't attempt this; use a keyboard shortcut
4. **Deployment target**: the test target's deployment target must match the app's or availability branches will warn

## Common Tasks

### Adding a new setting
1. Add a `var` property to `QCSettingsManager` (plain property — there are no `setX()` methods)
2. Add a key to the private `Key` enum
3. Read it in `loadSettings()`, write it in `saveSettings()`, and include it in `logSettings()` — or, if it should persist immediately without "Save Settings", back it directly by UserDefaults like `snapshotFolderBookmark`/`isVoiceCommandEnabled` (then only `logSettings()` needs updating)
4. Add a computed property in `QCAppDelegate` if needed
5. Update `applySettings()` if it affects display
6. Add a round-trip test in `QCSettingsManagerTests`

### Adding a new transformation
1. Add IBAction in `QCAppDelegate`
2. Put any maths in `QCRotation` (and test it) rather than inline
3. Update `applySettings()`; apply to all `videoConnections`, not just the preview
4. Consider interactions with rotation position and mirror states
5. Add menu item in the XIB

### Debugging camera issues
- Check Console.app for the `com.jasonkristian.QCamera` subsystem
- Verify device appears in `AVCaptureDevice.DiscoverySession`
- `QCUsbWatcher` triggers `deviceCountChanged()` on hot-plug events
- Session restart logic in `startCaptureWithVideoDevice()`

## Future AI Assistant Notes

- This is an **AppKit** app, not SwiftUI - avoid suggesting SwiftUI solutions
- Settings persistence is via UserDefaults, not SwiftData or Core Data
- Camera capture uses AVFoundation's `AVCaptureSession`
- Keep the simple, focused architecture - this is intentionally a lightweight utility

---

*Last updated: September 20, 2026*
