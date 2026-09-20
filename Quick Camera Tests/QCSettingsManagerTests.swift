import CoreGraphics
import Foundation
import Testing

@testable import Quick_Camera

@Suite("Settings persistence")
@MainActor
struct QCSettingsManagerTests {

    /// Each test gets its own throwaway defaults suite, so the app's real preferences
    /// (including the chosen snapshots folder) are never touched.
    private func withTemporaryDefaults(_ body: (UserDefaults, String) throws -> Void) rethrows {
        let suiteName = "com.simonguest.QCamera.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, suiteName)
    }

    @Test("An empty suite yields the documented defaults")
    func defaultsWhenNothingSaved() {
        withTemporaryDefaults { defaults, suiteName in
            let settings = QCSettingsManager(defaults: defaults, domain: suiteName)
            #expect(settings.isMirrored == false)
            #expect(settings.isUpsideDown == false)
            #expect(settings.isBorderless == false)
            #expect(settings.isAspectRatioFixed == false)
            #expect(settings.position == 0)
            #expect(settings.windowFrame == nil)
            #expect(settings.snapshotFolderBookmark == nil)
        }
    }

    @Test("Saved display settings come back after a reload")
    func displaySettingsRoundTrip() {
        withTemporaryDefaults { defaults, suiteName in
            let saved = QCSettingsManager(defaults: defaults, domain: suiteName)
            saved.isMirrored = true
            saved.isUpsideDown = true
            saved.isBorderless = true
            saved.isAspectRatioFixed = true
            saved.position = 3
            saved.deviceName = "Test Camera"
            saved.saveSettings()

            let reloaded = QCSettingsManager(defaults: defaults, domain: suiteName)
            #expect(reloaded.isMirrored)
            #expect(reloaded.isUpsideDown)
            #expect(reloaded.isBorderless)
            #expect(reloaded.isAspectRatioFixed)
            #expect(reloaded.position == 3)
            // deviceName tracks the live camera; the persisted one is exposed separately
            #expect(reloaded.savedDeviceName == "Test Camera")
        }
    }

    @Test("A usable window frame survives a reload")
    func windowFrameRoundTrips() {
        withTemporaryDefaults { defaults, suiteName in
            let saved = QCSettingsManager(defaults: defaults, domain: suiteName)
            saved.windowFrame = NSRect(x: 10, y: 20, width: 640, height: 480)
            saved.saveSettings()

            let reloaded = QCSettingsManager(defaults: defaults, domain: suiteName)
            #expect(reloaded.windowFrame == NSRect(x: 10, y: 20, width: 640, height: 480))
        }
    }

    @Test("Frames too small to be real are discarded", arguments: [CGFloat(0), 50, 100])
    func tinyWindowFramesAreIgnored(dimension: CGFloat) {
        withTemporaryDefaults { defaults, suiteName in
            let saved = QCSettingsManager(defaults: defaults, domain: suiteName)
            saved.windowFrame = NSRect(x: 10, y: 20, width: dimension, height: dimension)
            saved.saveSettings()

            let reloaded = QCSettingsManager(defaults: defaults, domain: suiteName)
            #expect(reloaded.windowFrame == nil)
        }
    }

    @Test("The snapshots folder persists without an explicit save")
    func snapshotBookmarkPersistsImmediately() {
        withTemporaryDefaults { defaults, suiteName in
            let bookmark = Data([0x01, 0x02, 0x03])
            let chosen = QCSettingsManager(defaults: defaults, domain: suiteName)
            chosen.snapshotFolderBookmark = bookmark
            // deliberately no saveSettings() - picking a folder should be enough

            let reloaded = QCSettingsManager(defaults: defaults, domain: suiteName)
            #expect(reloaded.snapshotFolderBookmark == bookmark)
        }
    }

    @Test("The voice command toggle persists without an explicit save")
    func voiceCommandTogglePersistsImmediately() {
        withTemporaryDefaults { defaults, suiteName in
            let toggled = QCSettingsManager(defaults: defaults, domain: suiteName)
            #expect(toggled.isVoiceCommandEnabled == false)
            toggled.isVoiceCommandEnabled = true
            // deliberately no saveSettings() - flipping the toggle should be enough

            let reloaded = QCSettingsManager(defaults: defaults, domain: suiteName)
            #expect(reloaded.isVoiceCommandEnabled)
        }
    }

    @Test("Clearing settings restores defaults and forgets the folder")
    func clearSettingsRestoresDefaults() {
        withTemporaryDefaults { defaults, suiteName in
            let settings = QCSettingsManager(defaults: defaults, domain: suiteName)
            settings.isMirrored = true
            settings.position = 2
            settings.windowFrame = NSRect(x: 10, y: 20, width: 640, height: 480)
            settings.snapshotFolderBookmark = Data([0x01])
            settings.saveSettings()

            settings.clearSettings()

            #expect(settings.isMirrored == false)
            #expect(settings.position == 0)
            #expect(settings.windowFrame == nil)
            #expect(settings.snapshotFolderBookmark == nil)
        }
    }

    @Test("Unsaved changes are dropped on reload")
    func unsavedChangesAreNotPersisted() {
        withTemporaryDefaults { defaults, suiteName in
            let settings = QCSettingsManager(defaults: defaults, domain: suiteName)
            settings.isMirrored = true
            settings.position = 1
            // no saveSettings() call

            let reloaded = QCSettingsManager(defaults: defaults, domain: suiteName)
            #expect(reloaded.isMirrored == false)
            #expect(reloaded.position == 0)
        }
    }
}
