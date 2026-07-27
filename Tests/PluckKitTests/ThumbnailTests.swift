import CoreGraphics
import XCTest

@testable import PluckKit

final class ThumbnailTests: XCTestCase {
    func testFitsTheLongEdgeAndKeepsTheAspectRatio() throws {
        let image = try TestImages.solid(width: 1600, height: 900, color: (10, 10, 10))
        let scaled = try Thumbnail.fit(image, maxEdge: 320)
        XCTAssertEqual(scaled.width, 320)
        XCTAssertEqual(scaled.height, 180)
    }

    func testTheLongEdgeIsWhicheverEdgeIsLonger() throws {
        let image = try TestImages.solid(width: 900, height: 1600, color: (10, 10, 10))
        let scaled = try Thumbnail.fit(image, maxEdge: 320)
        XCTAssertEqual(scaled.height, 320)
        XCTAssertEqual(scaled.width, 180)
    }

    /// Upscaling a small cutout to fill a grid cell only makes it blurry; the cell centres
    /// it instead.
    func testNeverUpscales() throws {
        let image = try TestImages.solid(width: 40, height: 30, color: (10, 10, 10))
        let scaled = try Thumbnail.fit(image, maxEdge: 320)
        XCTAssertEqual(scaled.width, 40)
        XCTAssertEqual(scaled.height, 30)
    }

    /// An extreme panorama must not round its short edge to zero — `CGImage` refuses, and
    /// the grid would show a decode failure for an image that is perfectly fine.
    func testTheShortEdgeNeverCollapses() throws {
        let image = try TestImages.solid(width: 4000, height: 3, color: (10, 10, 10))
        let scaled = try Thumbnail.fit(image, maxEdge: 320)
        XCTAssertEqual(scaled.width, 320)
        XCTAssertGreaterThanOrEqual(scaled.height, 1)
    }

    func testTransparencySurvivesTheRescale() throws {
        let image = try TestImages.rgba(width: 800, height: 800) { x, _ in
            x < 400 ? (255, 0, 0, 255) : (0, 0, 0, 0)
        }
        let pixels = try TestImages.pixels(of: try Thumbnail.fit(image, maxEdge: 100))
        XCTAssertEqual(TestImages.pixel(pixels, 10, 50).a, 255)
        XCTAssertEqual(TestImages.pixel(pixels, 90, 50).a, 0)
    }

    func testEncodesToPNG() throws {
        let image = try TestImages.solid(width: 600, height: 600, color: (10, 10, 10))
        let data = try Thumbnail.pngData(for: image, maxEdge: 64)
        XCTAssertEqual(data.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }
}
