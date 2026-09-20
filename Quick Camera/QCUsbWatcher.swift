import AVFoundation

// MARK: - Protocol
@MainActor
public protocol QCUsbWatcherDelegate: AnyObject {
    func deviceCountChanged()
}

// MARK: - QCUsbWatcher Class
/* Watches for video capture devices appearing or disappearing (USB hot-plug, Continuity Camera, etc.)
   by key-value observing the device list of an AVCaptureDevice.DiscoverySession. Unlike the previous
   IOKit-based approach, AVFoundation only publishes devices once they are ready for capture, so no
   settle delay is needed before notifying the delegate. */
@MainActor
public final class QCUsbWatcher {
    // MARK: - Properties
    public weak var delegate: QCUsbWatcherDelegate?
    private let discoverySession: AVCaptureDevice.DiscoverySession
    private var devicesObservation: NSKeyValueObservation?

    // MARK: - Initialization
    public init() {
        discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified)

        // KVO can fire on any thread, so hop to the main actor before notifying
        devicesObservation = discoverySession.observe(\.devices) { [weak self] _, _ in
            Task { @MainActor in
                self?.delegate?.deviceCountChanged()
            }
        }
    }
}
