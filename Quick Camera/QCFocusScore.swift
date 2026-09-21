import Accelerate
import CoreVideo

/// Focus scoring for the voice-driven capture window: the mean absolute 3x3 Laplacian of
/// the downscaled luma plane, so sharper frames score higher. Deliberately free of
/// capture-session state so it can be unit tested with synthetic pixel buffers.
enum QCFocusScore {

    /// Scores the sharpness of a planar pixel buffer's first (luma) plane. The video data
    /// output is configured for 420f, so plane 0 is always 8-bit luma. Returns 0 for
    /// non-planar buffers.
    static func score(of pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let planeIndex = 0
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex)
        guard width > 0, height > 0,
            let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex)
        else { return 0 }

        var luma = vImage_Buffer(
            data: base, height: vImagePixelCount(height), width: vImagePixelCount(width),
            rowBytes: rowBytes)

        // Downscale to ~320px wide; sharpness ranking survives it and the convolution gets cheap
        let targetWidth = min(320, width)
        let targetHeight = max(1, height * targetWidth / width)
        var small = vImage_Buffer()
        guard
            vImageBuffer_Init(
                &small, vImagePixelCount(targetHeight), vImagePixelCount(targetWidth), 8,
                vImage_Flags(kvImageNoFlags)) == kvImageNoError
        else { return 0 }
        defer { free(small.data) }
        vImageScale_Planar8(&luma, &small, nil, vImage_Flags(kvImageNoFlags))

        var smallF = vImage_Buffer()
        guard
            vImageBuffer_Init(
                &smallF, small.height, small.width, 32, vImage_Flags(kvImageNoFlags))
                == kvImageNoError
        else { return 0 }
        defer { free(smallF.data) }
        vImageConvert_Planar8toPlanarF(&small, &smallF, 1.0, 0, vImage_Flags(kvImageNoFlags))

        var laplacian = vImage_Buffer()
        guard
            vImageBuffer_Init(
                &laplacian, smallF.height, smallF.width, 32, vImage_Flags(kvImageNoFlags))
                == kvImageNoError
        else { return 0 }
        defer { free(laplacian.data) }
        let kernel: [Float] = [
            0, -1, 0,
            -1, 4, -1,
            0, -1, 0,
        ]
        vImageConvolve_PlanarF(
            &smallF, &laplacian, nil, 0, 0, kernel, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))

        // vImageBuffer_Init may pad rows, so sum the |Laplacian| row by row
        var absSum: Float = 0
        for row in 0..<Int(laplacian.height) {
            let rowPointer = laplacian.data
                .advanced(by: row * laplacian.rowBytes)
                .assumingMemoryBound(to: Float.self)
            var rowSum: Float = 0
            vDSP_svemg(rowPointer, 1, &rowSum, vDSP_Length(laplacian.width))
            absSum += rowSum
        }
        return absSum / Float(laplacian.width * laplacian.height)
    }
}
