import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import PluckKit

final class CoreMLEngineTests: XCTestCase {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testMissingModelReportsMissingNotBroken() async {
        let url = Self.repositoryRoot.appendingPathComponent("does/not/exist.mlpackage")
        do {
            _ = try await CoreMLEngine.load(id: "ghost", modelURL: url)
            XCTFail("loading an absent model must fail")
        } catch {
            XCTAssertEqual((error as? PluckError)?.kind, .modelMissing)
        }
    }

    func testUnreadableModelReportsLoadFailure() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluck-coreml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fake = directory.appendingPathComponent("Broken.mlpackage")
        try Data("not a model".utf8).write(to: fake)

        do {
            _ = try await CoreMLEngine.load(id: "broken", modelURL: fake, cacheRoot: directory)
            XCTFail("compiling garbage must fail")
        } catch {
            XCTAssertEqual((error as? PluckError)?.kind, .modelLoadFailed)
        }
    }

    /// The real thing, when the maintainer's converted model happens to be on this machine
    /// (`Scripts/convert-birefnet.py` puts it there). CI has no 94 MB package, so this skips
    /// rather than fails — but on the machine that ships the model, it runs.
    func testRealInferenceOnFurFixture() async throws {
        let modelURL = Self.repositoryRoot.appendingPathComponent("models/weights/BiRefNetLite.mlpackage")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: modelURL.path),
            "models/weights/BiRefNetLite.mlpackage is not on this machine"
        )

        let fixture = Self.repositoryRoot.appendingPathComponent("Tests/Fixtures/fur-01.jpg")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixture.path), "fixture missing")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(fixture as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        let engine = try await CoreMLEngine.load(id: "birefnet-lite", modelURL: modelURL)
        let mask = try engine.mask(for: image)

        XCTAssertEqual(mask.width, image.width)
        XCTAssertEqual(mask.height, image.height)

        let pixels = try ImageBuffers.grayscale(from: mask).pixels
        let foreground = Double(pixels.count { $0 > 127 }) / Double(pixels.count)
        XCTAssertGreaterThan(foreground, 0.2, "the subject fills far more than this")
        XCTAssertLessThan(foreground, 0.8, "a mask this full means the background leaked in")
    }
}
