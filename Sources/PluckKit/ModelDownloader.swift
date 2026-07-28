import Foundation

/// The one network call PluckKit ever makes, behind a protocol so tests never reach it.
///
/// The caller names the file rather than being handed one: a download that can be resumed
/// has to write somewhere that outlives the attempt, and only the caller knows where that
/// is (`ModelRegistry` keeps it beside the models, on the same volume as the install).
public protocol ModelDownloading: Sendable {
    /// Streams `url` into `destination`, continuing from whatever is already there when the
    /// server allows it.
    ///
    /// On return `destination` holds the whole entity as the server described it — which is
    /// a claim about bytes arriving, not about them being the right bytes; that judgement
    /// belongs to the digest check and nowhere else. On throw, whatever arrived is left in
    /// place for the next attempt.
    func download(
        from url: URL,
        into destination: URL,
        onProgress: @Sendable @escaping (_ received: Int64, _ expected: Int64) -> Void
    ) async throws
}

/// Resumes with a hand-written `Range` request rather than `URLSession`'s `resumeData`.
///
/// `resumeData` is an opaque blob whose contents, validity window and server requirements
/// are all undocumented, it is only produced when a task is *cancelled* (not when the
/// connection dies, and never when the process does), and nothing about it can be asserted
/// in a test. `Range: bytes=N-` plus `If-Range` is three headers of plain HTTP that a
/// hundred-line python server can implement (`Scripts/serve-models.py`), which is what
/// makes "it really did resume" a deterministic, offline test rather than a hope.
public struct URLSessionModelDownloader: ModelDownloading {
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
    }

    public func download(
        from url: URL,
        into destination: URL,
        onProgress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws {
        let partial = try PartialFile(at: destination)
        defer { partial.close() }

        do {
            try await attempt(url: url, into: partial, onProgress: onProgress)
        } catch is RangeRejected {
            // The server says our offset is past the end of what it now has. Whatever we
            // are holding is not a prefix of the current entity, so the only way forward is
            // to stop holding it.
            try partial.discard()
            try await attempt(url: url, into: partial, onProgress: onProgress)
        }
    }

    private func attempt(
        url: URL,
        into partial: PartialFile,
        onProgress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        // Nothing about a 100 MB asset belongs in a URL cache, and a cached 200 served to a
        // request that carried a `Range` header would be indistinguishable from a server
        // that ignored the range.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // A validator without bytes, or bytes without a validator, is not a resumable
        // state: asking for `bytes=N-` while unable to say what entity those N bytes came
        // from is how a resume silently splices two different files together.
        if partial.size > 0, let validator = partial.validator {
            request.setValue("bytes=\(partial.size)-", forHTTPHeaderField: "Range")
            request.setValue(validator, forHTTPHeaderField: "If-Range")
        } else if partial.size > 0 {
            try partial.discard()
        }

        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let receiver = Receiver(partial: partial, onProgress: onProgress)
        try await receiver.run(request, on: session)
    }
}

/// Thrown for HTTP 416 so `download` can tell "start over" apart from a real failure.
private struct RangeRejected: Error {}

/// The bytes that have arrived so far, plus a sidecar naming the entity they came from.
///
/// The validator lives in a file rather than in memory because the interruption worth
/// surviving is the process ending — a `Ctrl-C` during `pluck models pull`, or a quit
/// while the Settings pane is downloading.
final class PartialFile: @unchecked Sendable {
    let url: URL
    private let validatorURL: URL
    private var handle: FileHandle
    private(set) var size: Int64

    init(at url: URL) throws {
        self.url = url
        self.validatorURL = url.appendingPathExtension("validator")
        let manager = FileManager.default
        try manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        size = Int64(try handle.seekToEnd())
    }

    var validator: String? {
        guard let data = try? Data(contentsOf: validatorURL), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func setValidator(_ value: String?) {
        guard let value else {
            try? FileManager.default.removeItem(at: validatorURL)
            return
        }
        try? Data(value.utf8).write(to: validatorURL, options: .atomic)
    }

    func append(_ data: Data) throws {
        try handle.write(contentsOf: data)
        size += Int64(data.count)
    }

    /// Empties the file in place, keeping the handle: the caller is mid-response and is
    /// about to write the replacement entity into it.
    func discard() throws {
        try handle.truncate(atOffset: 0)
        size = 0
        setValidator(nil)
    }

    func close() {
        try? handle.close()
    }
}

/// Drives one HTTP request, appending the body as it arrives.
///
/// A `URLSessionDataTask` with a delegate rather than the download task's temporary file,
/// because a download task that fails hands back nothing — the bytes it did receive go to
/// a system temp file that is deleted on failure, which is precisely the state resuming
/// exists to preserve. Here every chunk is in the partial file the moment it arrives, so an
/// interruption at 90% leaves 90% behind.
private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let partial: PartialFile
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var expected: Int64 = 0
    private var failure: (any Error)?

    init(partial: PartialFile, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.partial = partial
        self.onProgress = onProgress
    }

    func run(_ request: URLRequest, on session: URLSession) async throws {
        let task = session.dataTask(with: request)
        task.delegate = self
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { self.continuation = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func finish(_ error: (any Error)?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse else {
            failure = URLError(.badServerResponse)
            return .cancel
        }
        switch http.statusCode {
        case 206:
            // Trust the server's own account of what it is sending: a 206 whose range does
            // not start where we stopped would append a gap or a repeat, and the digest
            // would then fail at the end of a 94 MB download instead of here.
            guard let range = http.value(forHTTPHeaderField: "Content-Range"),
                  let (start, total) = Self.parseContentRange(range),
                  start == partial.size
            else {
                failure = URLError(.badServerResponse, userInfo: [
                    NSLocalizedDescriptionKey: "the server resumed from the wrong offset"
                ])
                return .cancel
            }
            expected = total
        case 200:
            // No range honoured — either we asked for none, or `If-Range` failed and the
            // server is sending the whole (possibly different) entity. Either way what we
            // had is not a prefix of what is coming.
            do {
                try partial.discard()
            } catch {
                failure = error
                return .cancel
            }
            partial.setValidator(Self.validator(of: http))
            expected = http.expectedContentLength > 0 ? http.expectedContentLength : 0
        case 416:
            failure = RangeRejected()
            return .cancel
        default:
            failure = URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from \(http.url?.absoluteString ?? "")"
            ])
            return .cancel
        }
        onProgress(partial.size, expected)
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try partial.append(data)
        } catch {
            failure = error
            dataTask.cancel()
            return
        }
        onProgress(partial.size, expected)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let failure {
            finish(failure)
        } else if let error {
            finish(error)
        } else if expected > 0, partial.size < expected {
            // A body that ends early without an error still ended early.
            finish(URLError(.networkConnectionLost))
        } else {
            finish(nil)
        }
    }

    /// `ETag` first, `Last-Modified` as the fallback, nil when the server offers neither —
    /// which downgrades the next attempt to a full download rather than a hopeful splice.
    private static func validator(of response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "ETag")
            ?? response.value(forHTTPHeaderField: "Last-Modified")
    }

    /// `bytes 100-999/1000` → (100, 1000). A `*` total is treated as unknown, and an
    /// unknown total means we cannot tell a complete download from a truncated one.
    private static func parseContentRange(_ value: String) -> (start: Int64, total: Int64)? {
        let parts = value.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "bytes ", with: "")
            .split(separator: "/")
        guard parts.count == 2,
              let total = Int64(parts[1]),
              let start = Int64(parts[0].split(separator: "-").first ?? "")
        else { return nil }
        return (start, total)
    }
}
