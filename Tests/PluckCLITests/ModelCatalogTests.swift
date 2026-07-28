import ArgumentParser
import Foundation
import XCTest

@testable import PluckCLI
import PluckKit

/// Nothing here touches the network: the catalog only ever reads the manifest compiled
/// into the binary and looks at what is already on disk.
final class EngineCatalogTests: XCTestCase {
    func testManifestIsCompiledIntoTheBinary() throws {
        let registry = try XCTUnwrap(EngineCatalog.registry, "the CLI must carry models/manifest.json")
        XCTAssertEqual(registry.manifest.models.map(\.id), ["birefnet-lite", "birefnet-lite-matting"])
    }

    func testVisionIsAlwaysInstalledAndIsTheDefault() {
        XCTAssertEqual(EngineCatalog.defaultEngineID, "vision")
        XCTAssertTrue(EngineCatalog.installed.contains { $0.id == "vision" && $0.installed })
        XCTAssertTrue(EngineCatalog.descriptor(for: "vision")?.builtIn == true)
    }

    func testEveryManifestModelIsListedExactlyOnce() throws {
        let registry = try XCTUnwrap(EngineCatalog.registry)
        for model in registry.manifest.models {
            let matches = EngineCatalog.all.filter { $0.id == model.id }
            XCTAssertEqual(matches.count, 1, model.id)
            XCTAssertEqual(matches.first?.builtIn, false)
            XCTAssertEqual(matches.first?.installed, registry.isInstalled(model.id))
        }
        XCTAssertEqual(EngineCatalog.all.count, EngineCatalog.installed.count + EngineCatalog.available.count)
    }

    /// One fallible lookup, not a nil beside a throw. "Never heard of it" and "not on this
    /// disk" are the same exit code and the same advice, and keeping them apart only gave
    /// the plan's check and the loader's check room to disagree.
    func testUnknownIdIsAMissingModel() async throws {
        XCTAssertNil(EngineCatalog.descriptor(for: "nope"))
        do {
            _ = try await EngineCatalog.engine(for: "nope")
            XCTFail("an unknown id cannot produce an engine")
        } catch {
            XCTAssertEqual((error as? PluckError)?.kind, .modelMissing)
        }
    }

    /// The path a plan cannot rule out: the descriptor says installed, and by the time the
    /// engine is asked for, the file is gone. Deleting the real model to prove it would be
    /// rude, so this asserts on whichever half of the pair this machine can show.
    func testAModelWithNothingOnDiskIsMissingAtLoadTime() async throws {
        let registry = try XCTUnwrap(EngineCatalog.registry)
        let uninstalled = registry.manifest.models.first { !registry.isInstalled($0.id) }
        try XCTSkipUnless(uninstalled != nil, "every manifest model is installed on this machine")
        let id = try XCTUnwrap(uninstalled).id

        XCTAssertEqual(EngineCatalog.descriptor(for: id)?.installed, false)
        do {
            _ = try await EngineCatalog.engine(for: id)
            XCTFail("an uninstalled model cannot produce an engine")
        } catch {
            XCTAssertEqual((error as? PluckError)?.kind, .modelMissing)
        }
    }

    func testAvailabilityMessageNamesOnlyWhatWorksNow() {
        let message = EngineCatalog.availabilityMessage
        XCTAssertTrue(message.contains("vision"), message)
        for engine in EngineCatalog.available {
            XCTAssertFalse(message.contains(engine.id), message)
        }
    }
}

final class ModelsCommandTests: XCTestCase {
    func testListParsesTheJSONFlag() throws {
        XCTAssertFalse(try Models.List.parse([]).json)
        XCTAssertTrue(try Models.List.parse(["--json"]).json)
    }

    func testPullRequiresAnIdAndAcceptsForce() throws {
        XCTAssertThrowsError(try Models.Pull.parse([]))
        let command = try Models.Pull.parse(["birefnet-lite", "--force"])
        XCTAssertEqual(command.id, "birefnet-lite")
        XCTAssertTrue(command.force)
    }

    func testPullingAnUnknownIdExitsThree() async throws {
        let command = try Models.Pull.parse(["definitely-not-a-model"])
        do {
            try await command.run()
            XCTFail("an unknown id cannot be pulled")
        } catch let code as ExitCode {
            XCTAssertEqual(code.rawValue, ExitStatus.modelProblem)
        }
    }

    /// Idempotence is the CLI's job as much as the registry's: an already-installed model
    /// exits 0 without a byte of traffic.
    func testPullingAnInstalledModelSucceedsWithoutDownloading() async throws {
        let installed = EngineCatalog.installed.first { !$0.builtIn }
        try XCTSkipUnless(installed != nil, "no downloadable model is installed on this machine")
        let command = try Models.Pull.parse([try XCTUnwrap(installed).id])
        try await command.run()
    }

    func testMegabytesReadsAsTheReleaseAssetSize() {
        XCTAssertEqual(Models.Pull.megabytes(82_602_435), "83 MB")
    }
}
