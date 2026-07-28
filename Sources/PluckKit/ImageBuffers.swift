import CoreGraphics
import CoreVideo
import Foundation

/// Pixel plumbing shared by the engines and the compositor.
///
/// Everything here normalizes into two canonical layouts so the rest of PluckKit never
/// has to branch on color space, bit depth or byte order:
/// - color: 8-bit RGBA, premultiplied last, sRGB
/// - mask:  8-bit grayscale, no alpha
enum ImageBuffers {
    /// Vision is happy to accept arbitrarily large images but latency and memory grow
    /// linearly, and the mask it produces carries no extra detail past a few megapixels.
    /// 50 MP is above every current camera's full-frame output, so downsampling beyond it
    /// costs nothing visible while bounding worst-case memory (a 100 MP scan would
    /// otherwise need ~400 MB just for the RGBA copy).
    static let maxEnginePixels = 50_000_000

    struct Gray: Sendable {
        var width: Int
        var height: Int
        var pixels: [UInt8]  // width * height, row-major
    }

    struct RGBA: Sendable {
        var width: Int
        var height: Int
        var pixels: [UInt8]  // width * height * 4, premultiplied RGBA
    }

    static let sRGB = CGColorSpaceCreateDeviceRGB()
    static let gray = CGColorSpaceCreateDeviceGray()

    static func rgba(from image: CGImage, width: Int? = nil, height: Int? = nil) throws -> RGBA {
        let w = width ?? image.width
        let h = height ?? image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        try pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw PluckError.processingFailed(underlying: nil)
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return RGBA(width: w, height: h, pixels: pixels)
    }

    static func grayscale(from image: CGImage, width: Int? = nil, height: Int? = nil) throws -> Gray {
        let w = width ?? image.width
        let h = height ?? image.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        try pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: gray,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                throw PluckError.processingFailed(underlying: nil)
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Gray(width: w, height: h, pixels: pixels)
    }

    static func makeImage(_ buffer: RGBA) throws -> CGImage {
        try makeImage(
            bytes: buffer.pixels,
            width: buffer.width,
            height: buffer.height,
            bytesPerPixel: 4,
            space: sRGB,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
    }

    static func makeImage(_ buffer: Gray) throws -> CGImage {
        try makeImage(
            bytes: buffer.pixels,
            width: buffer.width,
            height: buffer.height,
            bytesPerPixel: 1,
            space: gray,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        )
    }

    private static func makeImage(
        bytes: [UInt8],
        width: Int,
        height: Int,
        bytesPerPixel: Int,
        space: CGColorSpace,
        bitmapInfo: CGBitmapInfo
    ) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else {
            throw PluckError.processingFailed(underlying: nil)
        }
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * bytesPerPixel,
            bytesPerRow: width * bytesPerPixel,
            space: space,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw PluckError.processingFailed(underlying: nil)
        }
        return image
    }

    /// Returns a copy scaled to fit `maxPixels`, or nil when the image already fits.
    static func downsampled(_ image: CGImage, maxPixels: Int = maxEnginePixels) throws -> CGImage? {
        let total = image.width * image.height
        guard total > maxPixels, total > 0 else { return nil }
        let scale = (Double(maxPixels) / Double(total)).squareRoot()
        let w = max(1, Int((Double(image.width) * scale).rounded(.down)))
        let h = max(1, Int((Double(image.height) * scale).rounded(.down)))
        return try makeImage(rgba(from: image, width: w, height: h))
    }

    /// Bilinear (CoreGraphics `.high`) rescale of a grayscale mask. Nearest-neighbour would
    /// leave stair-stepped alpha edges after upscaling from the downsampled engine input.
    static func resizeMask(_ mask: CGImage, width: Int, height: Int) throws -> CGImage {
        guard mask.width != width || mask.height != height else { return mask }
        return try makeImage(grayscale(from: mask, width: width, height: height))
    }

    /// Stretches `image` into a new BGRA pixel buffer of exactly the requested size.
    /// Stretch, not aspect-fit: the converted model was traced through torchvision's
    /// `Resize((S, S))`, so letterboxing here would feed it something it never saw.
    static func pixelBuffer(from image: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw PluckError.processingFailed(underlying: nil)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else {
            throw PluckError.processingFailed(underlying: nil)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    static func grayscale(from pixelBuffer: CVPixelBuffer) throws -> CGImage {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer), width > 0, height > 0 else {
            throw PluckError.processingFailed(underlying: nil)
        }

        var out = [UInt8](repeating: 0, count: width * height)
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_OneComponent32Float:
            for y in 0..<height {
                let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
                for x in 0..<width {
                    out[y * width + x] = UInt8((min(max(row[x], 0), 1) * 255).rounded())
                }
            }
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<height {
                let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    out[y * width + x] = row[x]
                }
            }
        default:
            throw PluckError.processingFailed(underlying: nil)
        }
        return try makeImage(Gray(width: width, height: height, pixels: out))
    }
}
