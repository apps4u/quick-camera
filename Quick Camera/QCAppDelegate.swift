/* AVFoundation predates Swift concurrency annotations. AVCaptureSession is documented as safe to
   drive from a dedicated serial queue, which is what sessionQueue does, so the Sendable warnings
   it raises are not meaningful here. */
@preconcurrency import AVFoundation
import Cocoa
import CoreImage
import UniformTypeIdentifiers
import os

// MARK: - QCAppDelegate Class
@main
@MainActor
final class QCAppDelegate: NSObject, NSApplicationDelegate, QCUsbWatcherDelegate,
    AVCaptureVideoDataOutputSampleBufferDelegate, QCVoiceListenerDelegate
{

    // MARK: - USB Watcher
    let usb: QCUsbWatcher = QCUsbWatcher()
    func deviceCountChanged() {
        self.detectVideoDevices()
        self.startCaptureWithVideoDevice(defaultDevice: selectedDeviceIndex)
    }

    // MARK: - Voice Listener
    let voiceListener: QCVoiceListener = QCVoiceListener()
    private var voiceCommandMenuItem: NSMenuItem?

    func voiceListenerDidHearTrigger(durationSeconds: TimeInterval?) {
        let duration = durationSeconds ?? defaultVoiceCaptureDuration
        logger.info(
            "Voice command heard - starting capture window for \(duration, privacy: .public)s")
        startVoiceCaptureWindow(duration: duration)
    }

    func voiceListenerDidRefineDuration(durationSeconds: TimeInterval) {
        rescheduleVoiceCaptureWindow(duration: durationSeconds)
    }

    func voiceListener(failedWith message: String) {
        isVoiceCommandEnabled = false
        voiceCommandMenuItem?.state = .off
        self.errorMessage(message: message)
    }

    // MARK: - Interface Builder Outlets
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var selectSourceMenu: NSMenuItem!
    @IBOutlet weak var borderlessMenu: NSMenuItem!
    @IBOutlet weak var aspectRatioFixedMenu: NSMenuItem!
    @IBOutlet weak var mirroredMenu: NSMenuItem!
    @IBOutlet weak var upsideDownMenu: NSMenuItem!
    @IBOutlet weak var playerView: NSView!

    // MARK: - Settings Properties
    private var settings: QCSettingsManager { QCSettingsManager.shared }

    var isMirrored: Bool {
        get { settings.isMirrored }
        set { settings.isMirrored = newValue }
    }
    var isUpsideDown: Bool {
        get { settings.isUpsideDown }
        set { settings.isUpsideDown = newValue }
    }
    var position: Int {
        get { settings.position }
        set { settings.position = newValue }
    }
    var isBorderless: Bool {
        get { settings.isBorderless }
        set { settings.isBorderless = newValue }
    }
    var isAspectRatioFixed: Bool {
        get { settings.isAspectRatioFixed }
        set { settings.isAspectRatioFixed = newValue }
    }
    var deviceName: String {
        get { settings.deviceName }
        set { settings.deviceName = newValue }
    }
    var isVoiceCommandEnabled: Bool {
        get { settings.isVoiceCommandEnabled }
        set { settings.isVoiceCommandEnabled = newValue }
    }

    // MARK: - Window Properties
    var defaultBorderStyle: NSWindow.StyleMask = NSWindow.StyleMask.closable
    var windowTitle: String = "Quick Camera"
    let defaultDeviceIndex: Int = 0
    var selectedDeviceIndex: Int = 0

    var devices: [AVCaptureDevice]!
    var captureSession: AVCaptureSession!
    var captureLayer: AVCaptureVideoPreviewLayer!
    var videoOutput: AVCaptureVideoDataOutput!

    var input: AVCaptureDeviceInput!

    // MARK: - Capture Queues
    /* startRunning/stopRunning block, so session work stays off the main thread. AVCaptureSession
       has no async API and requires a serial queue, so GCD remains the right tool here. */
    private let sessionQueue = DispatchQueue(label: "com.simonguest.QCamera.session")
    private let videoDataQueue = DispatchQueue(label: "com.simonguest.QCamera.videoData")

    /// Written by captureOutput and read via videoDataQueue.sync, so videoDataQueue -
    /// not the main actor - serialises access to it.
    private nonisolated(unsafe) var latestFrame: CVImageBuffer?

    /// Reused across snapshots; building a CIContext per capture is expensive.
    private let ciContext = CIContext()

    // MARK: - Voice Capture Window
    /// How long "snap" records for when no duration is spoken.
    private let defaultVoiceCaptureDuration: TimeInterval = 3.0
    private var voiceCaptureFinishTask: Task<Void, Never>?
    private var voiceCaptureStartDate: Date?

    /// Like latestFrame, these are owned by videoDataQueue: captureOutput writes them and the
    /// main actor reads them via videoDataQueue.sync.
    private nonisolated(unsafe) var voiceCaptureActive = false
    private nonisolated(unsafe) var focusFrameCounter = 0
    /// The sharpest frame seen so far, as a deep copy: delegate buffers belong to the capture
    /// pool, and holding on to them starves the pool and stalls frame delivery.
    private nonisolated(unsafe) var bestVoiceFrame: (score: Float, buffer: CVPixelBuffer)?

    // MARK: - Logging
    private let logger = Logger(subsystem: "com.simonguest.QCamera", category: "QCAppDelegate")

    // MARK: - Error Handling
    func errorMessage(message: String) {
        let popup: NSAlert = NSAlert()
        popup.messageText = message
        popup.runModal()
    }

    // MARK: - Device Management
    func detectVideoDevices() {
        logger.info("Detecting video devices...")
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified)
        self.devices = discoverySession.devices
        if devices.isEmpty {
            let popup: NSAlert = NSAlert()
            popup.messageText =
                "Unfortunately, you don't appear to have any cameras connected. Goodbye for now!"
            popup.runModal()
            NSApp.terminate(nil)
        } else {
            logger.info("\(self.devices.count) devices found")
        }

        let deviceMenu: NSMenu = NSMenu()

        // Here we need to keep track of the current device (if selected) in order to keep it checked in the menu
        var currentDevice: AVCaptureDevice = self.devices[defaultDeviceIndex]
        if self.captureSession != nil, let activeDevice = self.input?.device {
            currentDevice = activeDevice
        } else {
            logger.info("first time - loadSettings")
            self.loadSettings()
        }
        self.selectedDeviceIndex = defaultDeviceIndex

        for (deviceIndex, device) in self.devices.enumerated() {
            let deviceMenuItem: NSMenuItem = NSMenuItem(
                title: device.localizedName, action: #selector(deviceMenuChanged), keyEquivalent: ""
            )
            deviceMenuItem.target = self
            deviceMenuItem.representedObject = deviceIndex
            if device == currentDevice {
                deviceMenuItem.state = .on
                self.selectedDeviceIndex = deviceIndex
            }
            if deviceIndex < 9 {
                deviceMenuItem.keyEquivalent = String(deviceIndex + 1)
            }
            deviceMenu.addItem(deviceMenuItem)
        }
        selectSourceMenu.submenu = deviceMenu
    }

    func startCaptureWithVideoDevice(defaultDevice: Int) {
        logger.info("Starting capture with device index \(defaultDevice)")
        let device: AVCaptureDevice = self.devices[defaultDevice]

        if captureSession != nil {

            // if we are "restarting" a session but the device is the same exit early
            guard self.input?.device != device else { return }

            let oldSession = captureSession
            sessionQueue.async { oldSession?.stopRunning() }
        }
        captureSession = AVCaptureSession()

        do {
            self.input = try AVCaptureDeviceInput(device: device)
            self.captureSession.addInput(input)

            // keep the most recent frame available for snapshot capture
            self.videoOutput = AVCaptureVideoDataOutput()
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            self.captureLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)

            self.playerView.layer = self.captureLayer
            self.playerView.layer?.backgroundColor = CGColor.black
            self.windowTitle = "Quick Camera: [\(device.localizedName)]"
            self.window.title = self.windowTitle
            self.deviceName = device.localizedName
            self.applySettings()

            let session = self.captureSession
            sessionQueue.async { session?.startRunning() }
        } catch {
            logger.error("Error while opening device: \(error.localizedDescription, privacy: .public)")
            self.errorMessage(
                message:
                    "Unfortunately, there was an error when trying to access the camera. Try again or select a different one."
            )
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    nonisolated func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // called on videoDataQueue, which owns latestFrame
        latestFrame = CMSampleBufferGetImageBuffer(sampleBuffer)

        // While a voice-driven capture window is active, keep a copy of the sharpest frame.
        if voiceCaptureActive, let pixelBuffer = latestFrame {
            focusFrameCounter &+= 1
            // score every 3rd frame: the Laplacian is cheap, but not free on the capture queue
            if focusFrameCounter % 3 == 0 {
                let score = QCFocusScore.score(of: pixelBuffer)
                if score > (bestVoiceFrame?.score ?? -.infinity),
                    let copy = Self.copyPixelBuffer(pixelBuffer)
                {
                    bestVoiceFrame = (score, copy)
                }
            }
        }
    }

    // MARK: - Settings Management
    func loadSettings() {
        settings.loadSettings()

        if self.isBorderless {
            self.removeBorder()
        }

        if let frame = settings.windowFrame {
            self.window.setContentSize(frame.size)
            self.window.setFrameOrigin(frame.origin)
        }
    }

    /* the preview layer and the snapshot video output each have their own connection,
       so display transformations are applied to both to keep saved images matching the screen */
    private var videoConnections: [AVCaptureConnection] {
        var connections: [AVCaptureConnection] = []
        if let previewConnection = captureLayer?.connection {
            connections.append(previewConnection)
        }
        if let outputConnection = videoOutput?.connection(with: .video) {
            connections.append(outputConnection)
        }
        return connections
    }

    func applySettings() {
        settings.logSettings(label: "applySettings")

        self.setRotation(self.position)
        for connection in videoConnections {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
        self.fixAspectRatio()

        self.borderlessMenu.state = isBorderless ? .on : .off
        self.mirroredMenu.state = isMirrored ? .on : .off
        self.upsideDownMenu.state = isUpsideDown ? .on : .off
        self.aspectRatioFixedMenu.state = isAspectRatioFixed ? .on : .off
    }

    // MARK: - Settings Actions
    @IBAction func saveSettings(_ sender: NSMenuItem) {
        settings.windowFrame = self.window.frame
        settings.saveSettings()
    }

    @IBAction func clearSettings(_ sender: NSMenuItem) {
        settings.clearSettings()
    }

    // MARK: - Display Actions
    @IBAction func mirrorHorizontally(_ sender: NSMenuItem) {
        logger.info("Mirror image menu item selected")
        isMirrored = !isMirrored
        self.applySettings()
    }

    func setRotation(_ position: Int) {
        for connection in videoConnections {
            let angle = QCRotation.angle(position: position, isUpsideDown: isUpsideDown)
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    @IBAction func mirrorVertically(_ sender: NSMenuItem) {
        logger.info("Mirror image vertically menu item selected")
        isUpsideDown = !isUpsideDown
        self.applySettings()
    }

    func swapWindowWidthAndHeight() {
        var currentSize: CGSize = self.window.contentLayoutRect.size
        swap(&currentSize.height, &currentSize.width)
        self.window.setContentSize(currentSize)
    }

    @IBAction func rotateLeft(_ sender: NSMenuItem) {
        logger.info("Rotate Left menu item selected with position \(self.position)")
        position = QCRotation.rotatedLeft(from: position)
        self.swapWindowWidthAndHeight()
        self.applySettings()
    }

    @IBAction func rotateRight(_ sender: NSMenuItem) {
        logger.info("Rotate Right menu item selected with position \(self.position)")
        position = QCRotation.rotatedRight(from: position)
        self.swapWindowWidthAndHeight()
        self.applySettings()
    }

    // MARK: - Display Helpers
    private func addBorder() {
        window.styleMask = defaultBorderStyle
        window.title = self.windowTitle
        self.window.level = .normal
        window.isMovableByWindowBackground = false
    }

    private func removeBorder() {
        defaultBorderStyle = window.styleMask
        self.window.styleMask = [.borderless, .resizable]
        self.window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.isMovableByWindowBackground = true
    }

    @IBAction func borderless(_ sender: NSMenuItem) {
        logger.info("Borderless menu item selected")
        if self.window.styleMask.contains(.fullScreen) {
            logger.info("Ignoring borderless command as window is full screen")
            return
        }
        isBorderless = !isBorderless
        sender.state = isBorderless ? .on : .off
        if isBorderless {
            removeBorder()
        } else {
            addBorder()
        }
        fixAspectRatio()
    }

    @IBAction func enterFullScreen(_ sender: NSMenuItem) {
        logger.info("Enter full screen menu item selected")
        playerView.window?.toggleFullScreen(self)
        // no effect when borderless is enabled ?
    }

    @IBAction func toggleFixAspectRatio(_ sender: NSMenuItem) {
        isAspectRatioFixed = !isAspectRatioFixed
        sender.state = isAspectRatioFixed ? .on : .off
        fixAspectRatio()
    }

    var isLandscape: Bool { QCRotation.isLandscape(position: position) }

    /// Native pixel dimensions of the active camera format, oriented to match the current rotation.
    private var activeVideoSize: CGSize? {
        guard let dimensions = input?.device.activeFormat.formatDescription.dimensions else {
            return nil
        }
        let width = CGFloat(dimensions.width)
        let height = CGFloat(dimensions.height)
        return isLandscape ? CGSize(width: width, height: height) : CGSize(width: height, height: width)
    }

    func fixAspectRatio() {
        guard isAspectRatioFixed, let size = activeVideoSize else {
            self.window.contentResizeIncrements = NSMakeSize(1.0, 1.0)
            return
        }
        self.window.contentAspectRatio = size

        var currentSize: CGSize = self.window.contentLayoutRect.size
        currentSize.height = currentSize.width * (size.height / size.width)
        logger.debug(
            "fixAspectRatio : \(size.width),\(size.height) - \(currentSize.width),\(currentSize.height)"
        )
        self.window.setContentSize(currentSize)
    }

    @IBAction func fitToActualSize(_ sender: NSMenuItem) {
        guard let size = activeVideoSize else { return }
        self.window.setContentSize(size)
    }

    @IBAction func saveImage(_ sender: NSMenuItem) {
        Task { await captureSnapshot() }
    }

    @objc func setSnapshotsFolder(_ sender: NSMenuItem) {
        Task { _ = await promptForSnapshotFolder() }
    }

    /// Captures the current camera frame and saves it silently to the snapshots
    /// folder, asking the user to choose one first if none is set.
    func captureSnapshot() async {
        guard captureSession != nil else { return }
        guard let cgImage = currentFrameImage() else {
            logger.error("No video frame available to save")
            self.errorMessage(
                message: "Unfortunately, there is no camera image available to save yet.")
            return
        }

        // ?? can't take an async right-hand side, so the fallback prompt is spelled out
        var folder: URL? = resolveSnapshotFolder()
        if folder == nil {
            folder = await promptForSnapshotFolder()
        }
        guard let folder else { return }
        saveSnapshot(cgImage, in: folder)
    }

    /* the video output connection already applies the same rotation and mirroring
       as the on-screen preview, so the frame is used as delivered */
    private func currentFrameImage() -> CGImage? {
        guard let frame = videoDataQueue.sync(execute: { latestFrame }) else { return nil }
        let ciImage: CIImage = CIImage(cvImageBuffer: frame)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    private func saveSnapshot(_ cgImage: CGImage, in folder: URL) {
        let accessing: Bool = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        let fileURL: URL = QCSnapshotFile.uniqueURL(
            forFilename: QCSnapshotFile.filename(for: Date.now), in: folder)
        guard
            let destination = CGImageDestinationCreateWithURL(
                fileURL as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            logger.error("Could not create image destination for \(fileURL.path, privacy: .public)")
            self.errorMessage(
                message: "Unfortunately, the image could not be saved to the snapshots folder.")
            return
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        if CGImageDestinationFinalize(destination) {
            logger.info("Saved snapshot to \(fileURL.path, privacy: .public)")
            flashPreview()
        } else {
            logger.error("Could not write snapshot to \(fileURL.path, privacy: .public)")
            self.errorMessage(
                message: "Unfortunately, the image could not be saved to the snapshots folder.")
        }
    }

    /* Shutter-style flash to confirm the snapshot. A sound would be the obvious choice,
       but NSSound trips a sandbox mach-lookup denial for com.apple.audioanalyticsd. */
    private func flashPreview() {
        guard let hostLayer = playerView.layer else { return }
        let flashLayer: CALayer = CALayer()
        flashLayer.frame = playerView.bounds
        flashLayer.backgroundColor = CGColor.white
        flashLayer.opacity = 0
        hostLayer.addSublayer(flashLayer)

        let animation: CABasicAnimation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.85
        animation.toValue = 0
        animation.duration = 0.25
        CATransaction.begin()
        CATransaction.setCompletionBlock { flashLayer.removeFromSuperlayer() }
        flashLayer.add(animation, forKey: "flash")
        CATransaction.commit()
    }

    private func resolveSnapshotFolder() -> URL? {
        guard let bookmark = settings.snapshotFolderBookmark else { return nil }
        var isStale: Bool = false
        guard
            let url = try? URL(
                resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                bookmarkDataIsStale: &isStale)
        else { return nil }
        if isStale,
            let refreshed = try? url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        {
            settings.snapshotFolderBookmark = refreshed
        }
        return url
    }

    private func promptForSnapshotFolder() async -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder where snapshots will be saved"

        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        do {
            settings.snapshotFolderBookmark = try url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            return url
        } catch {
            logger.error(
                "Could not create bookmark for snapshots folder: \(error.localizedDescription, privacy: .public)"
            )
            self.errorMessage(message: "Unfortunately, that folder could not be used for snapshots.")
            return nil
        }
    }

    // MARK: - Device Menu Actions
    @objc func deviceMenuChanged(_ sender: NSMenuItem) {
        logger.info("Device Menu changed")
        guard sender.state != .on, let deviceIndex = sender.representedObject as? Int else {
            // selected the active device, so nothing to do here
            return
        }

        // set the checkbox on the currently selected device
        for menuItem in selectSourceMenu.submenu?.items ?? [] {
            menuItem.state = .off
        }
        sender.state = .on

        self.startCaptureWithVideoDevice(defaultDevice: deviceIndex)
    }

    // MARK: - Voice Capture Window

    /// Starts a timed capture window: captureOutput scores frames for sharpness while it is
    /// active, and the sharpest one is saved when it ends.
    private func startVoiceCaptureWindow(duration: TimeInterval) {
        let alreadyActive = videoDataQueue.sync { voiceCaptureActive }
        guard !alreadyActive else {
            logger.info("Capture window already active; ignoring voice trigger")
            return
        }
        videoDataQueue.sync {
            voiceCaptureActive = true
            focusFrameCounter = 0
            bestVoiceFrame = nil
        }
        voiceCaptureStartDate = Date.now
        scheduleVoiceCaptureFinish(after: duration)
    }

    /// Adjusts the end of the active window when the listener hears the duration late
    /// ("snap" then "snap five"), measured from when the window actually started.
    private func rescheduleVoiceCaptureWindow(duration: TimeInterval) {
        let active = videoDataQueue.sync { voiceCaptureActive }
        guard active, let startDate = voiceCaptureStartDate else { return }
        logger.info("Capture window rescheduled to \(duration, privacy: .public)s")
        scheduleVoiceCaptureFinish(after: duration - Date.now.timeIntervalSince(startDate))
    }

    private func scheduleVoiceCaptureFinish(after seconds: TimeInterval) {
        voiceCaptureFinishTask?.cancel()
        voiceCaptureFinishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(seconds, 0)))
            guard !Task.isCancelled else { return }
            await self?.finishVoiceCaptureWindow()
        }
    }

    /// Ends the capture window and saves the sharpest frame it saw.
    private func finishVoiceCaptureWindow() async {
        voiceCaptureStartDate = nil
        let best: (score: Float, buffer: CVPixelBuffer)? = videoDataQueue.sync {
            voiceCaptureActive = false
            defer { bestVoiceFrame = nil }
            return bestVoiceFrame
        }
        guard let best else {
            logger.info("Capture window finished with no frames to save")
            return
        }
        logger.info("Capture window finished; saving frame with focus score \(best.score)")

        let ciImage = CIImage(cvImageBuffer: best.buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            logger.error("Could not convert the best frame to an image")
            return
        }
        var folder: URL? = resolveSnapshotFolder()
        if folder == nil {
            folder = await promptForSnapshotFolder()
        }
        guard let folder else { return }
        saveSnapshot(cgImage, in: folder)
    }

    /// Deep-copies a pixel buffer so it can outlive the capture pool's ownership.
    private nonisolated static func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        var copyOut: CVPixelBuffer?
        guard
            CVPixelBufferCreate(
                kCFAllocatorDefault, CVPixelBufferGetWidth(source),
                CVPixelBufferGetHeight(source), CVPixelBufferGetPixelFormatType(source), nil,
                &copyOut) == kCVReturnSuccess, let copy = copyOut
        else { return nil }

        // colorimetry attachments keep CIImage rendering the copy like the original
        CVBufferPropagateAttachments(source, copy)

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        // row-by-row: the copy's rowBytes can differ from the source's
        for plane in 0..<max(CVPixelBufferGetPlaneCount(source), 1) {
            guard let sourceBase = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                let copyBase = CVPixelBufferGetBaseAddressOfPlane(copy, plane)
            else { return nil }
            let sourceRowBytes = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
            let copyRowBytes = CVPixelBufferGetBytesPerRowOfPlane(copy, plane)
            let rowBytes = min(sourceRowBytes, copyRowBytes)
            for row in 0..<CVPixelBufferGetHeightOfPlane(source, plane) {
                memcpy(
                    copyBase.advanced(by: row * copyRowBytes),
                    sourceBase.advanced(by: row * sourceRowBytes), rowBytes)
            }
        }
        return copy
    }

    // MARK: - Application Lifecycle
    /// Unit tests load the app as their host process; opening the camera for them is pointless
    /// (and turns the camera light on), so startup stops short of starting a capture session.
    private var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard !isRunningTests else { return }

        usb.delegate = self
        voiceListener.delegate = self
        addSnapshotMenuItems()
        startVoiceListenerIfEnabled()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCapture()
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    startCapture()
                } else {
                    reportCameraAccessDenied()
                }
            }
        default:
            reportCameraAccessDenied()
        }
    }

    private func startCapture() {
        detectVideoDevices()
        startCaptureWithVideoDevice(defaultDevice: defaultDeviceIndex)
    }

    private func reportCameraAccessDenied() {
        logger.error("Camera access was denied")
        errorMessage(
            message:
                "Quick Camera needs permission to use the camera. Grant access in System Settings > Privacy & Security > Camera, then open Quick Camera again."
        )
        NSApp.terminate(nil)
    }

    /* the menu is defined in MainMenu.xib; inserting these items programmatically
       next to Save Image avoids hand-editing the XIB */
    private func addSnapshotMenuItems() {
        guard
            let menu = NSApp.mainMenu?.items
                .compactMap({ $0.submenu })
                .first(where: { $0.items.contains { $0.action == #selector(saveImage(_:)) } }),
            let saveIndex = menu.items.firstIndex(where: {
                $0.action == #selector(saveImage(_:))
            })
        else { return }
        let folderItem: NSMenuItem = NSMenuItem(
            title: "Set Snapshots Folder…", action: #selector(setSnapshotsFolder(_:)),
            keyEquivalent: "")
        folderItem.target = self
        menu.insertItem(folderItem, at: saveIndex + 1)

        let voiceItem: NSMenuItem = NSMenuItem(
            title: "Listen for “\(QCVoiceCommand.triggerWord.capitalized)”",
            action: #selector(toggleVoiceCommand(_:)), keyEquivalent: "")
        voiceItem.target = self
        voiceItem.state = isVoiceCommandEnabled ? .on : .off
        menu.insertItem(voiceItem, at: saveIndex + 2)
        voiceCommandMenuItem = voiceItem
    }

    // MARK: - Voice Command Actions
    @objc func toggleVoiceCommand(_ sender: NSMenuItem) {
        logger.info("Voice command menu item selected")
        if voiceListener.isListening {
            voiceListener.stop()
            isVoiceCommandEnabled = false
            sender.state = .off
        } else {
            Task {
                let started = await voiceListener.start()
                isVoiceCommandEnabled = started
                sender.state = started ? .on : .off
            }
        }
    }

    private func startVoiceListenerIfEnabled() {
        guard isVoiceCommandEnabled else { return }
        Task {
            let started = await voiceListener.start()
            isVoiceCommandEnabled = started
            voiceCommandMenuItem?.state = started ? .on : .off
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

