import CoreGraphics
import Foundation
import ImageIO
import PluckKit
import UniformTypeIdentifiers
import XCTest

@testable import PluckCLI

/// The only tests here that touch Vision. They skip rather than fail where the system
/// model cannot run (headless CI, VMs without a supported compute device).
final class EndToEndTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/tmp")

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluck-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Red disc on white — the same unambiguous subject PluckKit's own tests use.
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

    private func skipIfEngineUnavailable(_ outcomes: [ItemOutcome]) throws {
        if outcomes.contains(where: { $0.failure?.kind == .engineUnavailable }) {
            throw XCTSkip("Vision unavailable in this environment")
        }
    }

    func testSingleFileWritesTransparentPNGBesideInput() async throws {
        let input = try writeSubjectJPEG(named: "subject.jpg")
        let plan = try RunPlan.make(
            inputs: [input], outputDirectory: nil, force: false,
            model: "vision", background: nil, json: false
        )
        let outcomes = await Runner(plan: plan).run()
        try skipIfEngineUnavailable(outcomes)

        let expected = directory.appendingPathComponent("subject.png").path
        guard case .success(let value) = try XCTUnwrap(outcomes.first).result else {
            return XCTFail("expected success, got \(outcomes)")
        }
        XCTAssertEqual(value.output, expected)
        XCTAssertEqual(value.width, 480)
        XCTAssertEqual(value.height, 320)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected))
        XCTAssertEqual(ExitStatus.resolve(outcomes), 0)

        let written = try ImageLoader.load(contentsOf: URL(fileURLWithPath: expected))
        XCTAssertEqual(written.width, 480)
        XCTAssertTrue(written.alphaInfo != .none, "cutout must carry alpha")
    }

    func testExistingOutputIsPreservedUntilForced() async throws {
        let input = try writeSubjectJPEG(named: "subject.jpg")
        let output = directory.appendingPathComponent("subject.png")
        try Data("not an image".utf8).write(to: output)

        let plan = try RunPlan.make(
            inputs: [input], outputDirectory: nil, force: false,
            model: "vision", background: nil, json: false
        )
        let outcomes = await Runner(plan: plan).run()
        XCTAssertEqual(outcomes.first?.failure?.kind, .outputExists)
        XCTAssertEqual(ExitStatus.resolve(outcomes), 1)
        XCTAssertEqual(try Data(contentsOf: output).count, 12)

        let forced = try RunPlan.make(
            inputs: [input], outputDirectory: nil, force: true,
            model: "vision", background: nil, json: false
        )
        let forcedOutcomes = await Runner(plan: forced).run()
        try skipIfEngineUnavailable(forcedOutcomes)
        XCTAssertNil(forcedOutcomes.first?.failure)
        XCTAssertGreaterThan(try Data(contentsOf: output).count, 12)
    }

    func testBatchCreatesOutputDirectoryAndKeepsGoingAfterAFailure() async throws {
        let good = try writeSubjectJPEG(named: "subject.jpg")
        let missing = directory.appendingPathComponent("gone.jpg").path
        let outputDirectory = directory.appendingPathComponent("out").path

        let plan = try RunPlan.make(
            inputs: [missing, good], outputDirectory: outputDirectory, force: false,
            model: "vision", background: "#ffffff", json: false
        )
        let outcomes = await Runner(plan: plan).run()
        try skipIfEngineUnavailable(outcomes)

        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(outcomes[0].failure?.kind, .imageLoadFailed)
        XCTAssertNil(outcomes[1].failure, "a failing input must not abort the batch")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory + "/subject.png"))
        XCTAssertEqual(ExitStatus.resolve(outcomes), 1)
    }

    func testTwoInputsMappingToOneOutputFailTheSecond() async throws {
        let first = try writeSubjectJPEG(named: "subject.jpg")
        let nested = directory.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let second = nested.appendingPathComponent("subject.jpg").path
        try FileManager.default.copyItem(atPath: first, toPath: second)

        let plan = try RunPlan.make(
            inputs: [first, second], outputDirectory: directory.appendingPathComponent("out").path,
            force: true, model: "vision", background: nil, json: false
        )
        let outcomes = await Runner(plan: plan).run()
        try skipIfEngineUnavailable(outcomes)
        XCTAssertEqual(outcomes[1].failure?.kind, .outputExists)
    }
}
