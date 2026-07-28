import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import PluckCLI

/// What actually lands on stdout — the only channel the CLI's contract says a caller has
/// to read. Everything else in these targets tests the values that *would* be printed;
/// this one redirects the file descriptor and reads the bytes back.
final class CommandOutputTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/tmp")

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluck-stdout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Runs `body` with fd 1 pointed at a pipe and fd 2 at /dev/null, and hands back
    /// everything written to stdout. The payloads here are a line or two, comfortably
    /// under the pipe buffer, so reading after the fact cannot deadlock.
    private func captureStandardOutput(
        _ body: () async throws -> Void
    ) async -> (output: String, error: (any Error)?) {
        let pipe = Pipe()
        let savedOut = dup(STDOUT_FILENO)
        let savedError = dup(STDERR_FILENO)
        let devNull = open("/dev/null", O_WRONLY)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(devNull, STDERR_FILENO)

        var thrown: (any Error)?
        do { try await body() } catch { thrown = error }

        fflush(stdout)
        dup2(savedOut, STDOUT_FILENO)
        dup2(savedError, STDERR_FILENO)
        close(savedOut)
        close(savedError)
        close(devNull)
        try? pipe.fileHandleForWriting.close()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(decoding: data, as: UTF8.self), thrown)
    }

    private func records(_ output: String) throws -> [[String: Any]] {
        try output.split(separator: "\n").map { line in
            try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                "not JSON: \(line)"
            )
        }
    }

    /// A `--json` run that fails during setup used to print nothing whatsoever on stdout:
    /// exit 3, a sentence of English on stderr, and an agent left to parse prose or guess.
    func testJSONSetupFailureIsReportedOnStandardOutput() async throws {
        let (output, error) = await captureStandardOutput {
            let command = try Pluck.parse(["photo.jpg", "--model", "nope", "--json"])
            try await command.run()
        }

        XCTAssertEqual((error as? ExitCode)?.rawValue, 3)
        let records = try records(output)
        XCTAssertEqual(records.count, 1, "exactly one run-level record: \(output)")
        XCTAssertEqual(records[0]["ok"] as? Bool, false)
        XCTAssertEqual(records[0]["error"] as? String, "model_missing")
        XCTAssertTrue((records[0]["message"] as? String ?? "").contains("nope"), output)
    }

    func testJSONArgumentFailureIsReportedOnStandardOutput() async throws {
        let (output, error) = await captureStandardOutput {
            let command = try Pluck.parse(["photo.jpg", "--background", "blue", "--json"])
            try await command.run()
        }

        XCTAssertEqual((error as? ExitCode)?.rawValue, 1)
        let records = try records(output)
        XCTAssertEqual(records.count, 1, output)
        XCTAssertEqual(records[0]["error"] as? String, "bad_arguments")
    }

    /// Without `--json` stdout stays empty — it belongs to payload, and there is none.
    func testPlainSetupFailurePrintsNothingOnStandardOutput() async throws {
        let (output, error) = await captureStandardOutput {
            let command = try Pluck.parse(["photo.jpg", "--model", "nope"])
            try await command.run()
        }
        XCTAssertEqual((error as? ExitCode)?.rawValue, 3)
        XCTAssertTrue(output.isEmpty, output)
    }

    /// The batch runs concurrently now, so the order records come back in is not the order
    /// the work finished in. Callers pair NDJSON with argv positionally; they get the
    /// order they asked in.
    func testBatchRecordsKeepInputOrderDespiteConcurrency() async throws {
        let good = try writeSubjectJPEG(named: "subject.jpg")
        let missingFirst = directory.appendingPathComponent("gone-a.jpg").path
        let missingLast = directory.appendingPathComponent("gone-b.jpg").path
        let inputs = [missingFirst, good, missingLast]

        let plan = try RunPlan.make(
            inputs: inputs, outputDirectory: directory.appendingPathComponent("out").path,
            force: true, model: "vision", background: nil, json: true
        )
        let (output, error) = await captureStandardOutput {
            let outcomes = await Runner(plan: plan).run()
            if outcomes.contains(where: { $0.failure?.kind == .engineUnavailable }) {
                throw XCTSkip("Vision unavailable in this environment")
            }
        }
        if let error { throw error }

        let records = try records(output)
        XCTAssertEqual(records.map { $0["input"] as? String }, inputs)
        // The two that failed still say where their PNG would have gone.
        XCTAssertEqual(records[0]["output"] as? String, directory.appendingPathComponent("out/gone-a.png").path)
        XCTAssertEqual(records[0]["engine"] as? String, "vision")
    }

    /// Red disc on white — the same unambiguous subject the rest of the suite uses.
    private func writeSubjectJPEG(named name: String) throws -> String {
        let width = 480
        let height = 320
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1))
        context.fillEllipse(in: CGRect(x: 140, y: 60, width: 200, height: 200))
        let image = try XCTUnwrap(context.makeImage())

        let url = directory.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url.path
    }
}
