import CoreGraphics
import Foundation
import XCTest

@testable import PluckKit

/// Returns a fixed mask regardless of input, so the pipeline's own wiring is what fails
/// when these tests fail — not Vision's opinion of a synthetic fixture.
private struct StubEngine: MattingEngine {
    let id = "stub"
    /// Left half foreground, right half background.
    func mask(for image: CGImage) throws -> CGImage {
        try TestImages.gray(width: image.width, height: image.height) { x, _ in
            x < image.width / 2 ? 255 : 0
        }
    }
}

private struct FailingEngine: MattingEngine {
    let id = "failing"
    func mask(for image: CGImage) throws -> CGImage {
        throw PluckError.noSubjectDetected
    }
}

final class PipelineTests: XCTestCase {
    private func png(_ image: CGImage) throws -> Data {
        try Compositor.pngData(for: image)
    }

    func testRunsFromAlreadyDecodedPixels() async throws {
        let input = try TestImages.solid(width: 8, height: 8, color: (200, 40, 40))
        let run = try await PluckPipeline(engine: StubEngine()).run(.image(input))

        XCTAssertEqual(run.width, 8)
        XCTAssertEqual(run.height, 8)

        let pixels = try TestImages.pixels(of: run.image)
        XCTAssertEqual(TestImages.pixel(pixels, 1, 4).a, 255)
        XCTAssertEqual(TestImages.pixel(pixels, 6, 4).a, 0)
    }

    func testRunsFromEncodedData() async throws {
        let data = try png(TestImages.solid(width: 6, height: 4, color: (10, 200, 10)))
        let run = try await PluckPipeline(engine: StubEngine()).run(.data(data))
        XCTAssertEqual(run.width, 6)
        XCTAssertEqual(run.height, 4)
    }

    func testRunsFromAFileURL() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pluck-pipeline-\(UUID().uuidString).png")
        try png(TestImages.solid(width: 5, height: 5, color: (0, 0, 200))).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let run = try await PluckPipeline(engine: StubEngine()).run(.file(url))
        XCTAssertEqual(run.width, 5)
    }

    /// The app used to hardcode a transparent background because it went through
    /// `Compositor.cutout` directly; routing it through the pipeline is only an
    /// improvement if the background actually travels.
    func testBackgroundReachesTheComposite() async throws {
        let input = try TestImages.solid(width: 8, height: 8, color: (200, 40, 40))
        let pipeline = PluckPipeline(engine: StubEngine(), background: .solid(.white))
        let pixels = try TestImages.pixels(of: try await pipeline.run(.image(input)).image)

        let masked = TestImages.pixel(pixels, 6, 4)
        XCTAssertEqual(masked.a, 255)
        XCTAssertEqual(masked.r, 255)
        XCTAssertEqual(masked.b, 255)
    }

    /// Both other members of `PluckRun` are there so callers do not decode or matte a
    /// second time to get them; a run that dropped them would compile just fine.
    func testTheRunKeepsTheInputAndTheMask() async throws {
        let input = try TestImages.solid(width: 8, height: 8, color: (200, 40, 40))
        let run = try await PluckPipeline(engine: StubEngine()).run(.image(input))

        XCTAssertEqual(run.input.width, 8)
        XCTAssertEqual(run.mask.width, 8)
        // The input survives untouched: it is the "before" half of the app's wipe.
        let before = try TestImages.pixels(of: run.input)
        XCTAssertEqual(TestImages.pixel(before, 6, 4).r, 200)
    }

    func testEngineFailuresPropagate() async throws {
        let input = try TestImages.solid(width: 4, height: 4, color: (0, 0, 0))
        do {
            _ = try await PluckPipeline(engine: FailingEngine()).run(.image(input))
            XCTFail("expected the engine's error to reach the caller")
        } catch let error as PluckError {
            XCTAssertEqual(error.kind, .noSubject)
        }
    }

    func testUnreadableDataFailsBeforeTheEngineRuns() async throws {
        do {
            _ = try await PluckPipeline(engine: FailingEngine()).run(.data(Data([0x00, 0x01])))
            XCTFail("expected a load failure")
        } catch let error as PluckError {
            // Not `.noSubject`: reaching the engine at all would mean the decode was skipped.
            XCTAssertEqual(error.kind, .imageLoadFailed)
        }
    }

    /// Same kind, same exit code, different sentence: a path that is not there is a caller
    /// mistake, and saying "unsupported file" about it sends the caller after the wrong fix.
    func testAMissingPathSaysSoRatherThanBlamingTheFormat() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluck-not-here-\(UUID().uuidString).png")
        XCTAssertThrowsError(try ImageLoader.load(contentsOf: missing)) { error in
            XCTAssertEqual((error as? PluckError)?.kind, .imageLoadFailed)
            XCTAssertTrue(
                error.localizedDescription.contains("no such file"),
                "got: \(error.localizedDescription)"
            )
        }
    }

    /// Only a file source has a name of its own. Naming the others is the shell's policy
    /// call — the app says "Cutout", the CLI would say something else.
    func testOnlyFilesSuggestAName() {
        let url = URL(fileURLWithPath: "/tmp/holiday photo.HEIC")
        XCTAssertEqual(PluckSource.file(url).suggestedName, "holiday photo")
        XCTAssertNil(PluckSource.data(Data([1])).suggestedName)
    }
}
