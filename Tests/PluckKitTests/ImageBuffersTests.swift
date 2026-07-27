import CoreGraphics
import XCTest

@testable import PluckKit

final class ImageBuffersTests: XCTestCase {
    func testImagesUnderTheLimitAreNotDownsampled() throws {
        let image = try TestImages.solid(width: 400, height: 300, color: (10, 20, 30))
        XCTAssertNil(try ImageBuffers.downsampled(image))
    }

    func testDownsamplingPreservesAspectRatioAndFitsBudget() throws {
        let image = try TestImages.circle(width: 4000, height: 2000)
        let out = try XCTUnwrap(try ImageBuffers.downsampled(image, maxPixels: 1_000_000))
        XCTAssertLessThanOrEqual(out.width * out.height, 1_000_000)
        XCTAssertEqual(Double(out.width) / Double(out.height), 2.0, accuracy: 0.01)
    }

    func testMaskResizeReturnsRequestedDimensions() throws {
        let mask = try TestImages.gray(width: 100, height: 50) { x, _ in x < 50 ? 0 : 255 }
        let resized = try ImageBuffers.resizeMask(mask, width: 400, height: 200)
        XCTAssertEqual(resized.width, 400)
        XCTAssertEqual(resized.height, 200)

        let gray = try ImageBuffers.grayscale(from: resized)
        XCTAssertEqual(gray.pixels[100 * 400 + 10], 0)
        XCTAssertEqual(gray.pixels[100 * 400 + 390], 255)
    }
}
