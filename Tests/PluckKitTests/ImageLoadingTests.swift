import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import PluckKit

/// Fixtures whose layout is *not* the canonical one the rest of the tests build by hand:
/// a wide-gamut profile, and pixels stored in an orientation other than the one they are
/// meant to be seen in. Both are what a phone actually hands over, and both were silently
/// normalized away — the first by rendering through device RGB, the second by a fallback
/// that returned the stored pixels unrotated.
///
/// Written to a temp directory in code rather than committed: a JPEG in the repository is
/// a binary nobody can review, and the two properties under test are exactly the ones an
/// opaque fixture would hide.
final class ImageLoadingTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/tmp")

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluck-loading-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Display P3

    /// A colour comfortably inside both gamuts, so the two encodings differ by arithmetic
    /// rather than by clipping — a saturated one would pin to 255 in either space and
    /// prove nothing.
    private static let p3Components: [CGFloat] = [0.2, 0.6, 0.3, 1]

    private func writeDisplayP3PNG() throws -> URL {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: Self.p3Components)))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let image = try XCTUnwrap(context.makeImage())

        let url = directory.appendingPathComponent("wide.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// What the same colour would have become had the buffer been rendered through sRGB.
    private func srgbEncoding() throws -> (UInt8, UInt8, UInt8) {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let color = try XCTUnwrap(CGColor(colorSpace: space, components: Self.p3Components))
        let converted = try XCTUnwrap(color.converted(
            to: ImageBuffers.sRGB, intent: .relativeColorimetric, options: nil
        ))
        let values = try XCTUnwrap(converted.components)
        return (
            UInt8((values[0] * 255).rounded()),
            UInt8((values[1] * 255).rounded()),
            UInt8((values[2] * 255).rounded())
        )
    }

    func testDisplayP3InputKeepsItsProfileThroughLoadAndComposite() throws {
        let url = try writeDisplayP3PNG()
        let loaded = try ImageLoader.load(contentsOf: url)
        XCTAssertEqual(loaded.colorSpace?.name, CGColorSpace.displayP3, "ImageIO lost the profile")

        // The canonical buffer stays in the file's space instead of being rendered into
        // device RGB, so the stored numbers are the numbers that were written.
        let buffer = try ImageBuffers.rgba(from: loaded)
        XCTAssertEqual(buffer.colorSpace.name, CGColorSpace.displayP3)
        let expected = (
            UInt8((Self.p3Components[0] * 255).rounded()),
            UInt8((Self.p3Components[1] * 255).rounded()),
            UInt8((Self.p3Components[2] * 255).rounded())
        )
        XCTAssertEqual(Int(buffer.pixels[0]), Int(expected.0), accuracy: 1)
        XCTAssertEqual(Int(buffer.pixels[1]), Int(expected.1), accuracy: 1)
        XCTAssertEqual(Int(buffer.pixels[2]), Int(expected.2), accuracy: 1)

        // …and the test is only worth anything because those numbers are not the sRGB ones.
        // Red is where the two encodings of this colour are furthest apart (51 against 0).
        let srgb = try srgbEncoding()
        XCTAssertGreaterThan(abs(Int(srgb.0) - Int(expected.0)), 8, "P3 and sRGB encodings are too close to tell apart")

        // The exported cutout carries the profile too — a P3 photo does not come back sRGB.
        let mask = try TestImages.gray(width: loaded.width, height: loaded.height) { _, _ in 255 }
        let cutout = try Compositor.cutout(image: loaded, mask: mask)
        XCTAssertEqual(cutout.colorSpace?.name, CGColorSpace.displayP3)
        let composed = try ImageBuffers.rgba(from: cutout)
        XCTAssertEqual(Int(composed.pixels[0]), Int(expected.0), accuracy: 1)
    }

    /// `--background` colours are defined in sRGB; writing their bytes straight into a P3
    /// buffer would quietly desaturate them. Only an unsaturated colour shows it — pure
    /// white and pure black happen to have the same bytes in both spaces.
    func testSolidBackgroundIsConvertedIntoTheWorkingSpace() throws {
        let url = try writeDisplayP3PNG()
        let loaded = try ImageLoader.load(contentsOf: url)
        let mask = try TestImages.gray(width: loaded.width, height: loaded.height) { _, _ in 0 }

        let colour = PluckColor(red: 0.2, green: 0.6, blue: 0.3)
        let out = try Compositor.compose(image: loaded, mask: mask, background: .solid(colour))
        let pixels = try ImageBuffers.rgba(from: out)

        // The sRGB colour re-encoded in P3 — i.e. the same colour, different numbers.
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let source = try XCTUnwrap(CGColor(colorSpace: ImageBuffers.sRGB, components: [0.2, 0.6, 0.3, 1]))
        let converted = try XCTUnwrap(source.converted(to: space, intent: .relativeColorimetric, options: nil))
        let values = try XCTUnwrap(converted.components)
        XCTAssertEqual(Int(pixels.pixels[0]), Int((values[0] * 255).rounded()), accuracy: 2)
        XCTAssertNotEqual(Int(pixels.pixels[0]), 51, "the sRGB bytes were written into a P3 buffer unchanged")
    }

    // MARK: - EXIF orientation

    /// Four quadrants, each a different colour: a rotation and a mirror of the same image
    /// are distinguishable only if both axes carry information.
    private func writeQuadrantJPEG(orientation: Int) throws -> URL {
        let width = 40
        let height = 20
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: ImageBuffers.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // CGContext is y-up, so the "top" half of the stored image is the high-y half.
        let quadrants: [(CGRect, CGFloat, CGFloat, CGFloat)] = [
            (CGRect(x: 0, y: 10, width: 20, height: 10), 1, 0, 0),   // top-left: red
            (CGRect(x: 20, y: 10, width: 20, height: 10), 0, 1, 0),  // top-right: green
            (CGRect(x: 0, y: 0, width: 20, height: 10), 0, 0, 1),    // bottom-left: blue
            (CGRect(x: 20, y: 0, width: 20, height: 10), 1, 1, 0)    // bottom-right: yellow
        ]
        for (rect, r, g, b) in quadrants {
            context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            context.fill(rect)
        }
        let image = try XCTUnwrap(context.makeImage())

        let url = directory.appendingPathComponent("oriented.jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ))
        // The TIFF dictionary is the one ImageIO actually writes; a top-level
        // `kCGImagePropertyOrientation` on a JPEG destination is silently dropped.
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: orientation],
            kCGImageDestinationLossyCompressionQuality: 1.0
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private static let palette: [(name: String, rgb: (Int, Int, Int))] = [
        ("red", (255, 0, 0)), ("green", (0, 255, 0)), ("blue", (0, 0, 255)), ("yellow", (255, 255, 0))
    ]

    /// Classifies a sample against the four quadrant colours rather than matching bytes:
    /// JPEG chroma subsampling drags neighbouring quadrants tens of levels into each other,
    /// and which corner a colour landed in is the only thing this test is asking.
    private func assertQuadrant(
        _ buffer: ImageBuffers.RGBA,
        _ x: Int,
        _ y: Int,
        _ expected: String,
        _ label: String,
        line: UInt = #line
    ) {
        let pixel = TestImages.pixel(buffer, x, y)
        let nearest = Self.palette.min { first, second in
            distance(pixel, first.rgb) < distance(pixel, second.rgb)
        }
        XCTAssertEqual(nearest?.name, expected, "\(label) — sampled \(pixel)", line: line)
    }

    private func distance(_ pixel: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ rgb: (Int, Int, Int)) -> Int {
        let dr = Int(pixel.r) - rgb.0
        let dg = Int(pixel.g) - rgb.1
        let db = Int(pixel.b) - rgb.2
        return dr * dr + dg * dg + db * db
    }

    /// Orientation 6 means "rotate 90° clockwise to display": a 40×20 file is a 20×40
    /// photograph, and its stored top-left corner belongs in the top-right.
    func testExifOrientationSixIsAppliedOnLoad() throws {
        let url = try writeQuadrantJPEG(orientation: 6)
        let loaded = try ImageLoader.load(contentsOf: url)

        XCTAssertEqual(loaded.width, 20, "orientation 6 swaps the axes")
        XCTAssertEqual(loaded.height, 40)

        let pixels = try ImageBuffers.rgba(from: loaded)
        assertQuadrant(pixels, 5, 5, "blue", "top-left should be the stored bottom-left")
        assertQuadrant(pixels, 15, 5, "red", "top-right should be the stored top-left")
        assertQuadrant(pixels, 15, 35, "green", "bottom-right should be the stored top-right")
        assertQuadrant(pixels, 5, 35, "yellow", "bottom-left should be the stored bottom-right")
    }

    /// The un-rotated control: same fixture, orientation 1, nothing moves.
    func testUnorientedImageIsLeftAlone() throws {
        let url = try writeQuadrantJPEG(orientation: 1)
        let loaded = try ImageLoader.load(contentsOf: url)

        XCTAssertEqual(loaded.width, 40)
        XCTAssertEqual(loaded.height, 20)

        let pixels = try ImageBuffers.rgba(from: loaded)
        assertQuadrant(pixels, 5, 5, "red", "top-left stays put")
        assertQuadrant(pixels, 35, 15, "yellow", "bottom-right stays put")
    }

    func testUnreadablePathIsReportedAsSuch() {
        XCTAssertThrowsError(try ImageLoader.load(contentsOf: directory.appendingPathComponent("nope.jpg"))) { error in
            guard case PluckError.imageLoadFailed(let reason) = error else {
                return XCTFail("expected imageLoadFailed, got \(error)")
            }
            XCTAssertEqual(reason, "no such file")
        }
    }
}
