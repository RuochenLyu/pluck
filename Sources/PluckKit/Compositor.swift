import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A background color in sRGB, components in 0...1 and *not* premultiplied.
public struct PluckColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = PluckColor(red: 1, green: 1, blue: 1)
    public static let black = PluckColor(red: 0, green: 0, blue: 0)
}

public enum PluckBackground: Sendable, Equatable {
    case transparent
    case solid(PluckColor)
}

/// Turns an image + mask into the shapes callers actually export.
public enum Compositor {
    /// Foreground over the requested background. Mask is resampled to the image size if needed.
    public static func compose(
        image: CGImage,
        mask: CGImage,
        background: PluckBackground = .transparent
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw PluckError.imageLoadFailed(reason: "image has zero width or height")
        }

        var source = try ImageBuffers.rgba(from: image)
        let alpha = try ImageBuffers.grayscale(from: mask, width: width, height: height)

        source.pixels.withUnsafeMutableBufferPointer { out in
            alpha.pixels.withUnsafeBufferPointer { a in
                switch background {
                case .transparent:
                    for i in 0..<(width * height) {
                        let k = Int(a[i])
                        let base = i * 4
                        // Premultiplied layout: scaling all four channels keeps color/alpha consistent.
                        out[base] = mul(out[base], k)
                        out[base + 1] = mul(out[base + 1], k)
                        out[base + 2] = mul(out[base + 2], k)
                        out[base + 3] = mul(out[base + 3], k)
                    }
                case .solid(let color):
                    let bgA = clamp8(color.alpha)
                    let bg = (
                        r: mul(clamp8(color.red), Int(bgA)),
                        g: mul(clamp8(color.green), Int(bgA)),
                        b: mul(clamp8(color.blue), Int(bgA))
                    )
                    for i in 0..<(width * height) {
                        let k = Int(a[i])
                        let base = i * 4
                        let fgA = mul(out[base + 3], k)
                        let inv = 255 - Int(fgA)
                        out[base] = mul(out[base], k) &+ mul(bg.r, inv)
                        out[base + 1] = mul(out[base + 1], k) &+ mul(bg.g, inv)
                        out[base + 2] = mul(out[base + 2], k) &+ mul(bg.b, inv)
                        out[base + 3] = fgA &+ mul(bgA, inv)
                    }
                }
            }
        }

        return try ImageBuffers.makeImage(source)
    }

    /// Transparent-background cutout — the default export.
    public static func cutout(image: CGImage, mask: CGImage) throws -> CGImage {
        try compose(image: image, mask: mask, background: .transparent)
    }

    /// The mask on its own, normalized to 8-bit grayscale (white = foreground).
    public static func maskOnly(_ mask: CGImage, width: Int? = nil, height: Int? = nil) throws -> CGImage {
        try ImageBuffers.makeImage(ImageBuffers.grayscale(from: mask, width: width, height: height))
    }

    public static func pngData(for image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw PluckError.processingFailed(underlying: nil)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PluckError.processingFailed(underlying: nil)
        }
        return data as Data
    }

    private static func mul(_ value: UInt8, _ factor: Int) -> UInt8 {
        UInt8((Int(value) * factor + 127) / 255)
    }

    private static func clamp8(_ value: Double) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }
}
