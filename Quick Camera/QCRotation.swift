import CoreGraphics

/// Pure rotation maths for the four display positions, kept free of capture-session
/// and window state so the behaviour can be reasoned about (and tested) on its own.
enum QCRotation {
    /// Position 0 = portrait, 1 = landscape left, 2 = portrait upside down, 3 = landscape right.
    static let positionCount = 4

    /// Rotation in degrees for a position, accounting for the vertical flip setting.
    static func angle(position: Int, isUpsideDown: Bool) -> CGFloat {
        let degrees = position * 90 + (isUpsideDown ? 180 : 0)
        return CGFloat(((degrees % 360) + 360) % 360)
    }

    /// Even positions keep the camera's native orientation; odd positions turn it on its side.
    static func isLandscape(position: Int) -> Bool {
        position % 2 == 0
    }

    static func rotatedLeft(from position: Int) -> Int {
        (position + positionCount - 1) % positionCount
    }

    static func rotatedRight(from position: Int) -> Int {
        (position + 1) % positionCount
    }
}
