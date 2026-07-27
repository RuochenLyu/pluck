import CoreGraphics
import Foundation
import XCTest

@testable import PluckKit

/// All fixtures are generated in code with a top-left origin, so tests never depend on
/// bundled assets, CGContext coordinate flips, or anything on the network.
enum TestImages {
    static func rgba(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = pixel(x, y)
                let i = (y * width + x) * 4
                bytes[i] = r
                bytes[i + 1] = g
                bytes[i + 2] = b
                bytes[i + 3] = a
            }
        }
        return try ImageBuffers.makeImage(ImageBuffers.RGBA(width: width, height: height, pixels: bytes))
    }

    static func gray(width: Int, height: Int, value: (Int, Int) -> UInt8) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                bytes[y * width + x] = value(x, y)
            }
        }
        return try ImageBuffers.makeImage(ImageBuffers.Gray(width: width, height: height, pixels: bytes))
    }

    static func solid(width: Int, height: Int, color: (UInt8, UInt8, UInt8)) throws -> CGImage {
        try rgba(width: width, height: height) { _, _ in (color.0, color.1, color.2, 255) }
    }

    /// White field with a centered filled circle — high contrast, unambiguous subject.
    static func circle(
        width: Int,
        height: Int,
        color: (UInt8, UInt8, UInt8) = (220, 40, 40),
        radiusFraction: Double = 0.3
    ) throws -> CGImage {
        let cx = Double(width) / 2
        let cy = Double(height) / 2
        let r = Double(min(width, height)) * radiusFraction
        return try rgba(width: width, height: height) { x, y in
            let dx = Double(x) - cx
            let dy = Double(y) - cy
            return (dx * dx + dy * dy) <= r * r ? (color.0, color.1, color.2, 255) : (255, 255, 255, 255)
        }
    }

    /// Reads back an image as premultiplied RGBA with a top-left origin.
    static func pixels(of image: CGImage) throws -> ImageBuffers.RGBA {
        try ImageBuffers.rgba(from: image)
    }

    static func pixel(_ buffer: ImageBuffers.RGBA, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * buffer.width + x) * 4
        return (buffer.pixels[i], buffer.pixels[i + 1], buffer.pixels[i + 2], buffer.pixels[i + 3])
    }
}

/// Vision refuses to run in some environments (headless CI, VMs without the required
/// compute device). Those runs skip rather than fail — the engine contract is still honored.
func skipIfEngineUnavailable(_ error: any Error) throws {
    if case PluckError.engineUnavailable(let reason) = error {
        throw XCTSkip("Vision unavailable in this environment: \(reason)")
    }
}
