import Foundation
import XCTest

@testable import PluckCLI
import PluckKit

final class ExitStatusTests: XCTestCase {
    private func outcome(_ kind: FailureKind?) -> ItemOutcome {
        guard let kind else {
            return .success(input: "a.jpg", ItemSuccess(output: "a.png", width: 1, height: 1, durationMs: 1))
        }
        return .failure(input: "a.jpg", kind, "boom")
    }

    func testAllSuccessIsZero() {
        XCTAssertEqual(ExitStatus.resolve([outcome(nil), outcome(nil)]), 0)
        XCTAssertEqual(ExitStatus.resolve([]), 0)
    }

    func testOnlyNoSubjectIsTwo() {
        XCTAssertEqual(ExitStatus.resolve([outcome(nil), outcome(.noSubject)]), 2)
    }

    func testModelProblemWinsOverEverything() {
        XCTAssertEqual(ExitStatus.resolve([outcome(.noSubject), outcome(.modelMissing)]), 3)
        XCTAssertEqual(ExitStatus.resolve([outcome(.imageLoadFailed), outcome(.modelMissing)]), 3)
    }

    func testOtherErrorsBeatNoSubject() {
        XCTAssertEqual(ExitStatus.resolve([outcome(.noSubject), outcome(.imageLoadFailed)]), 1)
        XCTAssertEqual(ExitStatus.resolve([outcome(.outputExists)]), 1)
        XCTAssertEqual(ExitStatus.resolve([outcome(.engineUnavailable)]), 1)
    }
}

final class FailureMappingTests: XCTestCase {
    func testPluckErrorsMapToSlugs() {
        XCTAssertEqual(ItemFailure.from(PluckError.noSubjectDetected, context: "a.jpg").kind, .noSubject)
        XCTAssertEqual(ItemFailure.from(PluckError.modelMissing(id: "x"), context: "a.jpg").kind, .modelMissing)
        XCTAssertEqual(ItemFailure.from(PluckError.engineUnavailable(reason: "vm"), context: "a.jpg").kind, .engineUnavailable)
        XCTAssertEqual(ItemFailure.from(PluckError.imageLoadFailed(reason: "bad"), context: "a.jpg").kind, .imageLoadFailed)
        XCTAssertEqual(ItemFailure.from(PluckError.processingFailed(underlying: nil), context: "a.jpg").kind, .processingFailed)
        XCTAssertEqual(ItemFailure.from(CocoaError(.fileWriteNoPermission), context: "a.jpg").kind, .writeFailed)
    }

    func testPathContextIsAddedByTheCLINotTheLibrary() {
        let failure = ItemFailure.from(PluckError.noSubjectDetected, context: "photos/a.jpg")
        XCTAssertTrue(failure.message.hasPrefix("photos/a.jpg: "), failure.message)
        XCTAssertTrue(failure.message.contains("No subject"), failure.message)
    }
}

final class JSONReportTests: XCTestCase {
    private func object(_ line: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    func testSuccessRecord() throws {
        let line = JSONReport.line(
            for: .success(input: "a.jpg", ItemSuccess(output: "out/a.png", width: 640, height: 480, durationMs: 42)),
            engine: "vision"
        )
        XCTAssertFalse(line.contains("\n"))
        let json = try object(line)
        XCTAssertEqual(json["input"] as? String, "a.jpg")
        XCTAssertEqual(json["output"] as? String, "out/a.png")
        XCTAssertEqual(json["width"] as? Int, 640)
        XCTAssertEqual(json["height"] as? Int, 480)
        XCTAssertEqual(json["durationMs"] as? Int, 42)
        XCTAssertEqual(json["engine"] as? String, "vision")
        XCTAssertEqual(json["ok"] as? Bool, true)
    }

    func testFieldOrderIsStable() {
        let line = JSONReport.line(
            for: .success(input: "a.jpg", ItemSuccess(output: "a.png", width: 2, height: 3, durationMs: 4)),
            engine: "vision"
        )
        XCTAssertEqual(
            line,
            #"{"input":"a.jpg","output":"a.png","width":2,"height":3,"durationMs":4,"engine":"vision","ok":true}"#
        )
    }

    func testQuotingEscapesControlCharacters() {
        XCTAssertEqual(JSONReport.quote("a\"b\\c\nd"), #""a\"b\\c\nd""#)
    }

    func testFailureRecordCarriesSlugAndMessage() throws {
        let line = JSONReport.line(
            for: .failure(
                input: "a.jpg",
                output: "out/a.png",
                .noSubject,
                "a.jpg: No subject was detected in this image."
            ),
            engine: "vision"
        )
        let json = try object(line)
        XCTAssertEqual(json["ok"] as? Bool, false)
        XCTAssertEqual(json["error"] as? String, "no_subject")
        XCTAssertEqual(json["message"] as? String, "a.jpg: No subject was detected in this image.")
        // Both fields used to be dropped from failure records. `output` is what the caller
        // needs to know which file is not there — it never saw the path, the CLI derived
        // it — and `engine` is what tells it whether another `--model` is worth a retry.
        XCTAssertEqual(json["output"] as? String, "out/a.png")
        XCTAssertEqual(json["engine"] as? String, "vision")
    }

    /// Nothing to name when the item never had a destination — `-` never became a file.
    func testFailureRecordOmitsOutputWhenThereIsNone() throws {
        let line = JSONReport.line(for: .failure(input: "-", .imageLoadFailed, "-: no data on stdin"), engine: "vision")
        let json = try object(line)
        XCTAssertNil(json["output"])
        XCTAssertEqual(json["engine"] as? String, "vision")
    }

    /// A run that dies during setup has no items, so it used to produce no stdout at all
    /// under `--json` — the caller's only signal was an exit code.
    func testSetupErrorsGetARunLevelRecord() throws {
        let json = try object(JSONReport.line(
            for: SetupError(message: "unknown model “nope”.", exitCode: 3, slug: SetupError.modelMissing)
        ))
        XCTAssertEqual(json["ok"] as? Bool, false)
        XCTAssertEqual(json["error"] as? String, "model_missing")
        XCTAssertEqual(json["message"] as? String, "unknown model “nope”.")
        XCTAssertNil(json["input"], "there is no item this failure belongs to")
    }

    func testPathsAreNotEscaped() throws {
        let line = JSONReport.line(
            for: .success(input: "/tmp/a.jpg", ItemSuccess(output: "/tmp/a.png", width: 1, height: 1, durationMs: 0)),
            engine: "vision"
        )
        XCTAssertTrue(line.contains("/tmp/a.png"), line)
        XCTAssertFalse(line.contains("\\/"), line)
    }
}
