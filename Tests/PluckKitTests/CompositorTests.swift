import CoreGraphics
import ImageIO
import XCTest

@testable import PluckKit

final class CompositorTests: XCTestCase {
    private let width = 64
    private let height = 32

    private func redImage() throws -> CGImage {
        try TestImages.solid(width: width, height: height, color: (255, 0, 0))
    }

    /// Left half background (0), right half foreground (255).
    private func splitMask() throws -> CGImage {
        try TestImages.gray(width: width, height: height) { x, _ in x < 32 ? 0 : 255 }
    }

    func testCutoutProducesTransparentBackgroundAndOpaqueSubject() throws {
        let out = try Compositor.cutout(image: redImage(), mask: splitMask())
        XCTAssertEqual(out.width, width)
        XCTAssertEqual(out.height, height)

        let px = try TestImages.pixels(of: out)
        let background = TestImages.pixel(px, 5, 16)
        XCTAssertEqual(background.a, 0)

        let subject = TestImages.pixel(px, 60, 16)
        XCTAssertEqual(subject.a, 255)
        XCTAssertEqual(subject.r, 255)
        XCTAssertEqual(subject.g, 0)
        XCTAssertEqual(subject.b, 0)
    }

    func testPartialMaskProducesPartialAlpha() throws {
        let mask = try TestImages.gray(width: width, height: height) { _, _ in 128 }
        let px = try TestImages.pixels(of: Compositor.cutout(image: redImage(), mask: mask))
        let p = TestImages.pixel(px, 10, 10)
        XCTAssertEqual(Int(p.a), 128, accuracy: 1)
        // Premultiplied: color must be scaled down with the alpha.
        XCTAssertEqual(Int(p.r), 128, accuracy: 2)
    }

    func testSolidBackgroundFillsMaskedOutRegion() throws {
        let out = try Compositor.compose(
            image: redImage(),
            mask: splitMask(),
            background: .solid(.white)
        )
        let px = try TestImages.pixels(of: out)

        let background = TestImages.pixel(px, 5, 16)
        XCTAssertEqual(background.a, 255)
        XCTAssertEqual(background.r, 255)
        XCTAssertEqual(background.g, 255)
        XCTAssertEqual(background.b, 255)

        let subject = TestImages.pixel(px, 60, 16)
        XCTAssertEqual(subject.a, 255)
        XCTAssertEqual(subject.r, 255)
        XCTAssertEqual(subject.g, 0)
    }

    func testSolidBackgroundBlendsHalfCoverageEdge() throws {
        let mask = try TestImages.gray(width: width, height: height) { _, _ in 128 }
        let out = try Compositor.compose(
            image: redImage(),
            mask: mask,
            background: .solid(.black)
        )
        let p = TestImages.pixel(try TestImages.pixels(of: out), 10, 10)
        XCTAssertEqual(p.a, 255)
        XCTAssertEqual(Int(p.r), 128, accuracy: 2)
        XCTAssertEqual(Int(p.g), 0, accuracy: 1)
    }

    func testMaskSmallerThanImageIsResampledToImageSize() throws {
        let smallMask = try TestImages.gray(width: width / 2, height: height / 2) { x, _ in
            x < 16 ? 0 : 255
        }
        let out = try Compositor.cutout(image: redImage(), mask: smallMask)
        XCTAssertEqual(out.width, width)
        XCTAssertEqual(out.height, height)

        let px = try TestImages.pixels(of: out)
        XCTAssertEqual(TestImages.pixel(px, 2, 16).a, 0)
        XCTAssertEqual(TestImages.pixel(px, 62, 16).a, 255)
    }

    func testMaskOnlyExportKeepsDimensionsAndValues() throws {
        let out = try Compositor.maskOnly(splitMask())
        XCTAssertEqual(out.width, width)
        XCTAssertEqual(out.height, height)

        let gray = try ImageBuffers.grayscale(from: out)
        XCTAssertEqual(gray.pixels[16 * width + 5], 0)
        XCTAssertEqual(gray.pixels[16 * width + 60], 255)
    }

    func testPNGDataRoundTripsWithAlpha() throws {
        let data = try Compositor.pngData(for: Compositor.cutout(image: redImage(), mask: splitMask()))
        XCTAssertGreaterThan(data.count, 0)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)

        let px = try TestImages.pixels(of: decoded)
        XCTAssertEqual(TestImages.pixel(px, 5, 16).a, 0)
        XCTAssertEqual(TestImages.pixel(px, 60, 16).a, 255)
    }
}
