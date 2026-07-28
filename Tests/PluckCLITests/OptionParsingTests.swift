import XCTest

@testable import PluckCLI
import PluckKit

final class HexColorTests: XCTestCase {
    func testSixDigitWithAndWithoutHash() throws {
        let expected = PluckColor(red: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(HexColor.parse("#ff0000"), expected)
        XCTAssertEqual(HexColor.parse("ff0000"), expected)
        XCTAssertEqual(HexColor.parse("#FF0000"), expected)
    }

    func testShorthandExpands() throws {
        XCTAssertEqual(HexColor.parse("#fff"), PluckColor(red: 1, green: 1, blue: 1, alpha: 1))
        XCTAssertEqual(HexColor.parse("#000"), PluckColor(red: 0, green: 0, blue: 0, alpha: 1))
    }

    func testAlphaChannel() throws {
        let color = try XCTUnwrap(HexColor.parse("#00000080"))
        XCTAssertEqual(color.alpha, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(HexColor.parse("#0000")?.alpha, 0)
    }

    func testMidGrayComponents() throws {
        let color = try XCTUnwrap(HexColor.parse("#808080"))
        XCTAssertEqual(color.red, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(color.green, color.blue)
    }

    func testRejectsGarbage() {
        XCTAssertNil(HexColor.parse("white"))
        XCTAssertNil(HexColor.parse("#fffff"))  // 3/4/6/8 digits only
        XCTAssertNil(HexColor.parse("#fffffff"))
        XCTAssertNil(HexColor.parse("#"))
        XCTAssertNil(HexColor.parse(""))
        XCTAssertNil(HexColor.parse("#gggggg"))
    }
}

final class OutputPlanTests: XCTestCase {
    func testSiblingOutputKeepsDirectory() {
        XCTAssertEqual(OutputPlan.destination(forInput: "photos/a.jpg", outputDirectory: nil), "photos/a.png")
        XCTAssertEqual(OutputPlan.destination(forInput: "/tmp/a.heic", outputDirectory: nil), "/tmp/a.png")
    }

    func testBareFilenameStaysRelative() {
        XCTAssertEqual(OutputPlan.destination(forInput: "a.jpg", outputDirectory: nil), "a.png")
    }

    func testOutputDirectoryOverridesLocation() {
        XCTAssertEqual(OutputPlan.destination(forInput: "photos/a.jpg", outputDirectory: "out"), "out/a.png")
        XCTAssertEqual(OutputPlan.destination(forInput: "photos/a.jpg", outputDirectory: "out/"), "out/a.png")
        XCTAssertEqual(OutputPlan.destination(forInput: "a.jpg", outputDirectory: "/var/tmp"), "/var/tmp/a.png")
    }

    func testExtensionHandling() {
        XCTAssertEqual(OutputPlan.destination(forInput: "a.tar.gz", outputDirectory: nil), "a.tar.png")
        XCTAssertEqual(OutputPlan.destination(forInput: "noext", outputDirectory: nil), "noext.png")
        // A .png input maps onto itself: the existence check (or --force) decides from here.
        XCTAssertEqual(OutputPlan.destination(forInput: "a.png", outputDirectory: nil), "a.png")
    }

    func testIdentityNormalizesEquivalentSpellings() {
        XCTAssertEqual(OutputPlan.identity(of: "out/./a.png"), OutputPlan.identity(of: "out/a.png"))
    }

    /// `-o out.png` used to make a *directory* named `out.png` and exit 0 with the file
    /// hidden inside it. Anything driving this CLI without eyes on the filesystem — which
    /// is the audience it was designed for — would have believed it.
    func testAPngOutputIsAFileNotAFolderToPutItIn() {
        XCTAssertTrue(OutputPlan.namesAFile("out.png"))
        XCTAssertTrue(OutputPlan.namesAFile("/tmp/deep/cut.PNG"))
        XCTAssertFalse(OutputPlan.namesAFile("out"))
        XCTAssertFalse(OutputPlan.namesAFile("out/"))
        XCTAssertFalse(OutputPlan.namesAFile("cutouts.d"))
    }

    /// A directory that is really there outranks the suffix: someone with a folder called
    /// `renders.png` means the folder.
    func testAnExistingDirectoryWinsOverTheSuffix() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pluck-out-\(UUID().uuidString).png", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(OutputPlan.namesAFile(directory.path))
    }
}

final class RunPlanTests: XCTestCase {
    private func plan(
        _ inputs: [String],
        output: String? = nil,
        force: Bool = false,
        model: String = "vision",
        background: String? = nil,
        json: Bool = false
    ) throws -> RunPlan {
        try RunPlan.make(
            inputs: inputs, outputDirectory: output, force: force,
            model: model, background: background, json: json
        )
    }

    private func setupError(_ body: () throws -> RunPlan) throws -> SetupError {
        do {
            _ = try body()
            XCTFail("expected a SetupError")
            return SetupError(message: "", exitCode: 0)
        } catch let error as SetupError {
            return error
        }
    }

    func testFileItemsPairInputsWithDerivedOutputs() throws {
        let plan = try plan(["a.jpg", "b/c.jpg"], output: "out")
        XCTAssertEqual(plan.items, [
            WorkItem(source: .file(path: "a.jpg"), destination: .file(path: "out/a.png")),
            WorkItem(source: .file(path: "b/c.jpg"), destination: .file(path: "out/c.png"))
        ])
        XCTAssertFalse(plan.writesImageToStandardOutput)
        XCTAssertEqual(plan.background, .transparent)
    }

    func testASinglePngOutputIsTheDestinationItself() throws {
        let plan = try plan(["photos/a.jpg"], output: "cutouts/hero.png")
        XCTAssertEqual(plan.items, [
            WorkItem(source: .file(path: "photos/a.jpg"), destination: .file(path: "cutouts/hero.png"))
        ])
    }

    /// Two inputs and one filename cannot both be honoured, and picking a winner silently
    /// is how one of them disappears.
    func testManyInputsIntoOneFileIsRefused() throws {
        let error = try setupError { try plan(["a.jpg", "b.jpg"], output: "hero.png") }
        XCTAssertEqual(error.exitCode, 1)
        XCTAssertTrue(error.message.contains("directory"), error.message)
    }

    func testStdinGoesToStdout() throws {
        let plan = try plan(["-"])
        XCTAssertEqual(plan.items, [WorkItem(source: .standardInput, destination: .standardOutput)])
        XCTAssertTrue(plan.writesImageToStandardOutput)
    }

    func testBackgroundBecomesSolidColor() throws {
        XCTAssertEqual(try plan(["a.jpg"], background: "#ffffff").background, .solid(.white))
    }

    func testNoInputsIsAnError() throws {
        XCTAssertEqual(try setupError { try plan([]) }.exitCode, 1)
    }

    func testUnknownModelExitsThree() throws {
        let error = try setupError { try plan(["a.jpg"], model: "nope") }
        XCTAssertEqual(error.exitCode, 3)
        XCTAssertTrue(error.message.contains("vision"), error.message)
    }

    func testManifestModelThatIsNotInstalledPointsAtThePullCommand() throws {
        try XCTSkipUnless(
            EngineCatalog.descriptor(for: "birefnet-lite")?.installed == false,
            "birefnet-lite is installed on this machine"
        )
        let error = try setupError { try plan(["a.jpg"], model: "birefnet-lite") }
        XCTAssertEqual(error.exitCode, 3)
        XCTAssertTrue(error.message.contains("pluck models pull birefnet-lite"), error.message)
    }

    func testInvalidBackgroundExitsOne() throws {
        XCTAssertEqual(try setupError { try plan(["a.jpg"], background: "blue") }.exitCode, 1)
    }

    func testStdinRejectsCompanionArguments() throws {
        XCTAssertEqual(try setupError { try plan(["-", "a.jpg"]) }.exitCode, 1)
        XCTAssertEqual(try setupError { try plan(["-"], output: "out") }.exitCode, 1)
        // NDJSON and PNG bytes cannot share stdout.
        XCTAssertEqual(try setupError { try plan(["-"], json: true) }.exitCode, 1)
    }
}
