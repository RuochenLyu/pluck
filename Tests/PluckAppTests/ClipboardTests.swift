import Foundation
import PluckKit
import XCTest

@testable import PluckApp

private final class MockPasteboard: ImagePasteboard, @unchecked Sendable {
    var stored: (data: Data, name: String)?
    private(set) var written: [Data] = []

    init(stored: (data: Data, name: String)? = nil) {
        self.stored = stored
    }

    func readImage() -> (data: Data, name: String)? { stored }

    func writePNG(_ data: Data) { written.append(data) }
}

private func processed(_ bytes: [UInt8]) -> ProcessedImage {
    ProcessedImage(
        pngData: Data(bytes),
        thumbnailPNG: Data(bytes),
        width: 2,
        height: 2,
        suggestedName: "cut"
    )
}

final class ClipboardTests: XCTestCase {
    func testEmptyClipboardReportsNoImage() async {
        let pasteboard = MockPasteboard()
        let plucker = ClipboardPlucker(pasteboard: pasteboard) { _, _ in
            XCTFail("should not process without input")
            return processed([0])
        }
        let (outcome, result) = await plucker.run()
        XCTAssertEqual(outcome, .noImage)
        XCTAssertNil(result)
        XCTAssertTrue(pasteboard.written.isEmpty)
    }

    func testSuccessWritesCutoutBackToClipboard() async {
        let pasteboard = MockPasteboard(stored: (Data([9]), "cat"))
        let plucker = ClipboardPlucker(pasteboard: pasteboard) { data, name in
            XCTAssertEqual(data, Data([9]))
            XCTAssertEqual(name, "cat")
            return processed([1, 2, 3])
        }
        let (outcome, result) = await plucker.run()
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(result?.pngData, Data([1, 2, 3]))
        XCTAssertEqual(pasteboard.written, [Data([1, 2, 3])])
    }

    func testNoSubjectLeavesClipboardUntouched() async {
        let pasteboard = MockPasteboard(stored: (Data([9]), "cat"))
        let plucker = ClipboardPlucker(pasteboard: pasteboard) { _, _ in
            throw PluckError.noSubjectDetected
        }
        let (outcome, _) = await plucker.run()
        XCTAssertEqual(outcome, .noSubject)
        XCTAssertTrue(pasteboard.written.isEmpty)
    }

    func testUndecodableDataIsReportedAsNoImage() async {
        let pasteboard = MockPasteboard(stored: (Data([9]), "cat"))
        let plucker = ClipboardPlucker(pasteboard: pasteboard) { _, _ in
            throw PluckError.imageLoadFailed(reason: "garbage")
        }
        let (outcome, _) = await plucker.run()
        XCTAssertEqual(outcome, .noImage)
    }

    func testOtherFailuresAreGeneric() async {
        let pasteboard = MockPasteboard(stored: (Data([9]), "cat"))
        let plucker = ClipboardPlucker(pasteboard: pasteboard) { _, _ in
            throw PluckError.processingFailed(underlying: nil)
        }
        let (outcome, _) = await plucker.run()
        XCTAssertEqual(outcome, .failed)
    }
}
