import CoreGraphics
import Testing

@testable import Quick_Camera

@Suite("Rotation maths")
struct QCRotationTests {

    @Test(
        "Each position maps to its rotation angle",
        arguments: [(0, 0.0), (1, 90.0), (2, 180.0), (3, 270.0)])
    func angleForPosition(position: Int, expected: Double) {
        #expect(QCRotation.angle(position: position, isUpsideDown: false) == CGFloat(expected))
    }

    @Test(
        "Flipping vertically adds half a turn",
        arguments: [(0, 180.0), (1, 270.0), (2, 0.0), (3, 90.0)])
    func angleWhenUpsideDown(position: Int, expected: Double) {
        #expect(QCRotation.angle(position: position, isUpsideDown: true) == CGFloat(expected))
    }

    @Test("Angles stay within a single turn")
    func angleIsNormalised() {
        for position in 0..<QCRotation.positionCount {
            for isUpsideDown in [true, false] {
                let angle = QCRotation.angle(position: position, isUpsideDown: isUpsideDown)
                #expect(angle >= 0 && angle < 360)
            }
        }
    }

    @Test("Even positions are landscape, odd positions are not")
    func landscapePositions() {
        #expect(QCRotation.isLandscape(position: 0))
        #expect(!QCRotation.isLandscape(position: 1))
        #expect(QCRotation.isLandscape(position: 2))
        #expect(!QCRotation.isLandscape(position: 3))
    }

    @Test("Rotating right steps forward and wraps at the end")
    func rotateRightWraps() {
        #expect(QCRotation.rotatedRight(from: 0) == 1)
        #expect(QCRotation.rotatedRight(from: 2) == 3)
        #expect(QCRotation.rotatedRight(from: 3) == 0)
    }

    @Test("Rotating left steps back and wraps past zero")
    func rotateLeftWraps() {
        #expect(QCRotation.rotatedLeft(from: 3) == 2)
        #expect(QCRotation.rotatedLeft(from: 1) == 0)
        #expect(QCRotation.rotatedLeft(from: 0) == 3)
    }

    @Test("Four rotations in either direction return to the start")
    func fullTurnReturnsToStart() {
        var right = 2
        var left = 2
        for _ in 0..<QCRotation.positionCount {
            right = QCRotation.rotatedRight(from: right)
            left = QCRotation.rotatedLeft(from: left)
        }
        #expect(right == 2)
        #expect(left == 2)
    }
}
