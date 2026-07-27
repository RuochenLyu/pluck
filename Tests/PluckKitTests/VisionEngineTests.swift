import CoreGraphics
import XCTest

@testable import PluckKit

final class VisionEngineTests: XCTestCase {
    private let engine = VisionEngine()

    func testEngineID() {
        XCTAssertEqual(engine.id, "vision")
    }

    func testBlankImageReportsNoSubjectInsteadOfCrashing() async throws {
        let blank = try TestImages.solid(width: 512, height: 512, color: (128, 128, 128))
        do {
            _ = try await engine.mask(for: blank)
            XCTFail("expected noSubjectDetected for a blank image")
        } catch let error as PluckError {
            try skipIfEngineUnavailable(error)
            guard case .noSubjectDetected = error else {
                return XCTFail("expected noSubjectDetected, got \(error)")
            }
        }
    }

    func testMaskMatchesSourceDimensions() async throws {
        let image = try TestImages.circle(width: 600, height: 400)
        do {
            let mask = try await engine.mask(for: image)
            XCTAssertEqual(mask.width, image.width)
            XCTAssertEqual(mask.height, image.height)

            let gray = try ImageBuffers.grayscale(from: mask)
            let foreground = gray.pixels.count { $0 > 127 }
            XCTAssertGreaterThan(foreground, 0, "mask should mark some pixels as foreground")
            XCTAssertLessThan(foreground, gray.pixels.count, "mask should not cover the whole frame")
        } catch let error as PluckError {
            try skipIfEngineUnavailable(error)
            throw error
        }
    }

    func testEndToEndCutoutOfSyntheticSubject() async throws {
        let image = try TestImages.circle(width: 600, height: 400)
        do {
            let mask = try await engine.mask(for: image)
            let cutout = try Compositor.cutout(image: image, mask: mask)
            XCTAssertEqual(cutout.width, image.width)
            XCTAssertEqual(cutout.height, image.height)

            let png = try Compositor.pngData(for: cutout)
            XCTAssertGreaterThan(png.count, 0)

            let px = try TestImages.pixels(of: cutout)
            XCTAssertEqual(TestImages.pixel(px, 1, 1).a, 0, "image corner is background")
            XCTAssertEqual(TestImages.pixel(px, 300, 200).a, 255, "circle center is foreground")
        } catch let error as PluckError {
            try skipIfEngineUnavailable(error)
            throw error
        }
    }

    /// Over the 50 MP budget the engine downsamples before Vision and scales the mask back;
    /// callers must still get a mask at the original resolution.
    func testOversizedImageIsDownsampledAndMaskScaledBack() async throws {
        let image = try TestImages.circle(width: 9000, height: 6000)
        XCTAssertGreaterThan(image.width * image.height, ImageBuffers.maxEnginePixels)
        do {
            let mask = try await engine.mask(for: image)
            XCTAssertEqual(mask.width, 9000)
            XCTAssertEqual(mask.height, 6000)
        } catch let error as PluckError {
            try skipIfEngineUnavailable(error)
            if case .noSubjectDetected = error { return }
            throw error
        }
    }
}
