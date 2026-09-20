import Cocoa
import os

@MainActor
final class QCSettingsManager {
    // MARK: - Logging
    private let logger = Logger(subsystem: "com.jasonkristian.QCamera", category: "QCSettingsManager")

    // MARK: - User Defaults Keys
    private enum Key {
        static let deviceName = "deviceName"
        static let borderless = "borderless"
        static let mirrored = "mirrored"
        static let upsideDown = "upsideDown"
        static let aspectRatioFixed = "aspectRatioFixed"
        static let position = "position"
        static let snapshotFolderBookmark = "snapshotFolderBookmark"
        static let voiceCommandEnabled = "voiceCommandEnabled"
        static let frameX = "frameX"
        static let frameY = "frameY"
        static let frameWidth = "frameW"
        static let frameHeight = "frameH"
    }

    // MARK: - Properties
    var isMirrored = false
    var isUpsideDown = false
    var isBorderless = false
    var isAspectRatioFixed = false
    var position = 0
    var deviceName = "-"
    private(set) var savedDeviceName = "-"

    /// Window frame to restore at launch; nil when nothing usable has been saved.
    var windowFrame: NSRect?

    /// Security-scoped bookmark for the folder snapshots are written to. Backed directly by
    /// UserDefaults so the choice persists immediately, without an explicit "Save Settings".
    var snapshotFolderBookmark: Data? {
        get { defaults.data(forKey: Key.snapshotFolderBookmark) }
        set { defaults.set(newValue, forKey: Key.snapshotFolderBookmark) }
    }

    /// Whether the "snap" voice command is listening. Backed directly by UserDefaults so
    /// the toggle persists immediately, without an explicit "Save Settings".
    var isVoiceCommandEnabled: Bool {
        get { defaults.bool(forKey: Key.voiceCommandEnabled) }
        set { defaults.set(newValue, forKey: Key.voiceCommandEnabled) }
    }

    // MARK: - Storage
    private let defaults: UserDefaults
    private let domain: String?

    // MARK: - Singleton
    static let shared = QCSettingsManager()

    private convenience init() {
        self.init(defaults: .standard, domain: Bundle.main.bundleIdentifier)
    }

    /// Lets tests run against a throwaway suite instead of the app's real preferences.
    init(defaults: UserDefaults, domain: String?) {
        self.defaults = defaults
        self.domain = domain
        loadSettings()
    }

    // MARK: - Settings Management
    func loadSettings() {
        logSettings(label: "before loadSettings")

        savedDeviceName = defaults.string(forKey: Key.deviceName) ?? ""
        isBorderless = defaults.bool(forKey: Key.borderless)
        isMirrored = defaults.bool(forKey: Key.mirrored)
        isUpsideDown = defaults.bool(forKey: Key.upsideDown)
        isAspectRatioFixed = defaults.bool(forKey: Key.aspectRatioFixed)
        position = defaults.integer(forKey: Key.position)

        // a saved frame is only usable if it has real dimensions
        let width = CGFloat(defaults.float(forKey: Key.frameWidth))
        let height = CGFloat(defaults.float(forKey: Key.frameHeight))
        if width > 100 && height > 100 {
            let x = CGFloat(defaults.object(forKey: Key.frameX) as? Float ?? 100)
            let y = CGFloat(defaults.object(forKey: Key.frameY) as? Float ?? 100)
            windowFrame = NSRect(x: x, y: y, width: width, height: height)
            logger.debug("loaded : x:\(x),y:\(y),w:\(width),h:\(height)")
        } else {
            windowFrame = nil
        }

        logSettings(label: "after loadSettings")
    }

    func saveSettings() {
        logSettings(label: "saveSettings")

        defaults.set(deviceName, forKey: Key.deviceName)
        defaults.set(isBorderless, forKey: Key.borderless)
        defaults.set(isMirrored, forKey: Key.mirrored)
        defaults.set(isUpsideDown, forKey: Key.upsideDown)
        defaults.set(isAspectRatioFixed, forKey: Key.aspectRatioFixed)
        defaults.set(position, forKey: Key.position)

        if let windowFrame {
            defaults.set(Float(windowFrame.minX), forKey: Key.frameX)
            defaults.set(Float(windowFrame.minY), forKey: Key.frameY)
            defaults.set(Float(windowFrame.width), forKey: Key.frameWidth)
            defaults.set(Float(windowFrame.height), forKey: Key.frameHeight)
        }
    }

    func clearSettings() {
        if let domain {
            defaults.removePersistentDomain(forName: domain)
        }
        loadSettings()  // Reset to defaults
    }

    func logSettings(label: String) {
        logger.debug(
            """
            \(label, privacy: .public) : \(self.deviceName, privacy: .public),\
            \(self.savedDeviceName, privacy: .public),\
            \(self.isBorderless ? "+" : "-", privacy: .public)borderless,\
            \(self.isMirrored ? "+" : "-", privacy: .public)mirrored,\
            \(self.isUpsideDown ? "+" : "-", privacy: .public)upsideDown,\
            \(self.isAspectRatioFixed ? "+" : "-", privacy: .public)aspectRatioFixed,\
            \(self.snapshotFolderBookmark != nil ? "+" : "-", privacy: .public)snapshotFolder,\
            \(self.isVoiceCommandEnabled ? "+" : "-", privacy: .public)voiceCommand,\
            position:\(self.position)
            """
        )
    }
}
