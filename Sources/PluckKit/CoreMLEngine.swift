import Accelerate
import CoreGraphics
import CoreML
import Foundation

/// The downloadable high-quality path: a converted BiRefNet variant run through Core ML.
///
/// Everything the model needs to know about pixel values is already baked into it — the
/// ImageNet normalization is folded into the input layer by `Scripts/convert-birefnet.py`,
/// so Swift hands over a plain image and gets a 0–1 alpha field back.
/// A class, and unchecked: `MLModel` is not `Sendable`, but it is documented as safe to
/// call `prediction` on from several threads at once, which is exactly what `PluckQueue`
/// does with a shared engine. Wrapping it in an actor would serialize the one part of the
/// pipeline that is already allowed to run wide.
public final class CoreMLEngine: MattingEngine, @unchecked Sendable {
    public let id: String

    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let inputWidth: Int
    private let inputHeight: Int

    /// Loads an already-compiled `.mlmodelc`. Use `load(id:modelURL:)` for a `.mlpackage`.
    public init(id: String, compiledModelURL url: URL) throws {
        self.id = id

        let configuration = MLModelConfiguration()
        // Never `.all`. The Neural Engine cannot compile the gather chain that replaces
        // deformable convolution in this architecture: on the lite models it fails fast,
        // on the large ones it hangs — 37 minutes at 0% CPU, no error, no timeout
        // (research.md appendix A.6). The converter pins the same units for the same reason.
        configuration.computeUnits = .cpuAndGPU

        do {
            model = try MLModel(contentsOf: url, configuration: configuration)
        } catch {
            throw PluckError.modelLoadFailed(id: id, reason: error.localizedDescription)
        }

        let description = model.modelDescription
        guard let input = description.inputDescriptionsByName.first(where: { $0.value.imageConstraint != nil }),
              let constraint = input.value.imageConstraint
        else {
            throw PluckError.modelLoadFailed(id: id, reason: "the model has no image input")
        }
        guard let output = description.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })
        else {
            throw PluckError.modelLoadFailed(id: id, reason: "the model has no multi-array output")
        }

        inputName = input.key
        outputName = output.key
        inputWidth = constraint.pixelsWide
        inputHeight = constraint.pixelsHigh
        guard inputWidth > 0, inputHeight > 0 else {
            throw PluckError.modelLoadFailed(id: id, reason: "the model input has no fixed size")
        }
    }

    /// Loads a model from disk, compiling it first when it is a `.mlpackage`.
    ///
    /// Async only because `MLModel.compileModel(at:)` is: the synchronous spelling has been
    /// deprecated since macOS 13. The first compile of a 94 MB package takes 5–10 seconds,
    /// so the result is cached next to the other derived data — repeat loads are instant,
    /// and callers still get a synchronous `mask(for:)` afterwards.
    public static func load(id: String, modelURL: URL, cacheRoot: URL? = nil) async throws -> CoreMLEngine {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw PluckError.modelMissing(id: id)
        }
        if modelURL.pathExtension == "mlmodelc" {
            return try CoreMLEngine(id: id, compiledModelURL: modelURL)
        }
        let compiled = try await compile(id: id, modelURL: modelURL, cacheRoot: cacheRoot ?? defaultCacheRoot)
        return try CoreMLEngine(id: id, compiledModelURL: compiled)
    }

    public static var defaultCacheRoot: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Pluck/CompiledModels", isDirectory: true)
    }

    private static func compile(id: String, modelURL: URL, cacheRoot: URL) async throws -> URL {
        let fileManager = FileManager.default
        let cached = cacheRoot.appendingPathComponent("\(id).mlmodelc", isDirectory: true)
        if let sourceDate = modified(modelURL), let cacheDate = modified(cached), cacheDate >= sourceDate {
            return cached
        }

        let temporary: URL
        do {
            temporary = try await MLModel.compileModel(at: modelURL)
        } catch {
            throw PluckError.modelLoadFailed(id: id, reason: error.localizedDescription)
        }

        // A failure to cache is not a failure to load: the freshly compiled copy in the
        // temporary directory is perfectly usable for this process's lifetime.
        do {
            try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: cached.path) {
                _ = try fileManager.replaceItemAt(cached, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: cached)
            }
            return cached
        } catch {
            return temporary
        }
    }

    private static func modified(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    public func mask(for image: CGImage) throws -> CGImage {
        guard image.width > 0, image.height > 0 else {
            throw PluckError.imageLoadFailed(reason: "image has zero width or height")
        }

        let buffer = try ImageBuffers.pixelBuffer(from: image, width: inputWidth, height: inputHeight)
        let features = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(pixelBuffer: buffer)]
        )

        let prediction: any MLFeatureProvider
        do {
            prediction = try model.prediction(from: features)
        } catch {
            throw PluckError.processingFailed(underlying: error)
        }

        guard let array = prediction.featureValue(for: outputName)?.multiArrayValue else {
            throw PluckError.processingFailed(underlying: nil)
        }

        let gray = try alpha(from: array)
        guard gray.pixels.contains(where: { $0 > 8 }) else { throw PluckError.noSubjectDetected }
        return try ImageBuffers.resizeMask(
            ImageBuffers.makeImage(gray),
            width: image.width,
            height: image.height
        )
    }

    /// The output is (1, 1, S, S) alpha in 0–1, fp16 as converted. Read it as raw bytes
    /// rather than through `MLMultiArray`'s subscript: that path boxes every one of the
    /// million elements in an NSNumber.
    private func alpha(from array: MLMultiArray) throws -> ImageBuffers.Gray {
        let shape = array.shape.map(\.intValue)
        guard shape.count >= 2 else {
            throw PluckError.processingFailed(underlying: nil)
        }
        let height = shape[shape.count - 2]
        let width = shape[shape.count - 1]
        let count = width * height
        guard count > 0, array.count == count,
              array.strides.map(\.intValue).last == 1
        else {
            throw PluckError.processingFailed(underlying: nil)
        }

        var pixels = [UInt8](repeating: 0, count: count)
        switch array.dataType {
        case .float16:
            // vImage rather than Swift's Float16, which does not exist on x86_64 macOS.
            try array.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { throw PluckError.processingFailed(underlying: nil) }
                var source = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: base),
                    height: 1, width: vImagePixelCount(count), rowBytes: count * 2
                )
                var floats = [Float](repeating: 0, count: count)
                try floats.withUnsafeMutableBufferPointer { out in
                    var destination = vImage_Buffer(
                        data: out.baseAddress, height: 1,
                        width: vImagePixelCount(count), rowBytes: count * 4
                    )
                    guard vImageConvert_Planar16FtoPlanarF(&source, &destination, 0) == kvImageNoError else {
                        throw PluckError.processingFailed(underlying: nil)
                    }
                }
                pixels = floats.map(Self.quantize)
            }
        case .float32:
            array.withUnsafeBufferPointer(ofType: Float.self) { values in
                for index in 0..<count { pixels[index] = Self.quantize(values[index]) }
            }
        case .double:
            array.withUnsafeBufferPointer(ofType: Double.self) { values in
                for index in 0..<count { pixels[index] = Self.quantize(Float(values[index])) }
            }
        default:
            throw PluckError.processingFailed(underlying: nil)
        }
        return ImageBuffers.Gray(width: width, height: height, pixels: pixels)
    }

    private static func quantize(_ value: Float) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }
}
