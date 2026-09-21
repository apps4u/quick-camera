import CoreVideo
import Testing

@testable import Quick_Camera

@Suite("Focus scoring")
struct QCFocusScoreTests {

    /// Builds a 420f pixel buffer (the format the video data output delivers)
    /// whose luma plane is filled by `luma(x, y)`.
    private func makeBuffer(
        width: Int = 640, height: Int = 480, luma: (Int, Int) -> UInt8
    ) -> CVPixelBuffer? {
        var bufferOut: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &bufferOut)
        guard let buffer = bufferOut else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width { row[x] = luma(x, y) }
        }
        return buffer
    }

    @Test("A featureless frame scores zero")
    func flatFrameScoresZero() throws {
        let flat = try #require(makeBuffer { _, _ in 128 })
        #expect(QCFocusScore.score(of: flat) < 0.001)
    }

    @Test("A frame with hard edges outscores a smooth gradient")
    func edgesOutscoreGradient() throws {
        // 8px blocks survive the internal downscale; a 1px checkerboard would average away
        let blocks = try #require(makeBuffer { x, y in
            ((x / 8) + (y / 8)).isMultiple(of: 2) ? 0 : 255
        })
        let gradient = try #require(makeBuffer(width: 640) { x, _ in UInt8(x * 255 / 640) })
        #expect(QCFocusScore.score(of: blocks) > QCFocusScore.score(of: gradient))
    }
}
