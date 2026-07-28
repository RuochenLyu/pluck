import Foundation
import PluckKit

/// What each engine is called, and what it is for, in the user's language.
///
/// Lives in the app and not in PluckKit on purpose: the library's `EngineDescriptor.summary`
/// is developer copy the CLI prints ("BiRefNet_lite via Core ML, 1024px (MIT)"), and
/// `--model birefnet-lite-matting` is an interface agents type exactly. Neither is something
/// a person should have to read to answer "which one do I want for this photo".
///
/// The two BiRefNet models are a division of subject, not a quality ladder (research.md
/// A.6): lite produces crisp, decided edges and turns a wine glass into a solid object;
/// lite-matting keeps the soft band — 4.4% of pixels against lite's 1.2% — so hair stays
/// hair and glass stays see-through. Same size, same speed. Calling them "Fast" and "Best"
/// would be a lie that costs the user the shot they wanted.
///
/// An id with no entry here falls back to the manifest's own display name, so a model added
/// to `manifest.json` still renders — with its technical name, which is the honest default
/// for copy nobody has written yet.
enum EngineLabels {
    private static let birefnetLite = "birefnet-lite"
    private static let birefnetLiteMatting = "birefnet-lite-matting"

    static func name(_ id: String, fallback: String? = nil) -> String {
        switch id {
        case EngineCatalog.defaultEngineID: L.s("Apple Vision")
        case birefnetLite: L.s("Detail")
        case birefnetLiteMatting: L.s("Matting")
        default: fallback ?? id
        }
    }

    /// One sentence about what comes out, not about what it is made of.
    static func blurb(_ id: String) -> String? {
        switch id {
        case EngineCatalog.defaultEngineID: L.s("Instant, built into macOS.")
        case birefnetLite: L.s("Crisp, solid edges. Translucent things come out opaque.")
        case birefnetLiteMatting: L.s("Soft hair and true translucency — glass stays see-through.")
        default: nil
        }
    }

    /// How long one image takes. Vision is a system request measured in tens of milliseconds;
    /// a Core ML model is a second or two on the same machine (research.md A.6: 1.2–1.3 s
    /// warm). The first run of a downloaded model also pays a 5–10 second compile, which the
    /// status line says out loud rather than being averaged into a number here.
    static func pace(_ id: String) -> String {
        id == EngineCatalog.defaultEngineID ? L.s("instant") : L.s("~1–2 s")
    }

    static func paceDetail(_ id: String) -> String {
        id == EngineCatalog.defaultEngineID ? L.s("instant") : L.s("~1–2 s per image")
    }

    /// How a *result* names the engine that made it, or nil when there is nothing worth
    /// saying. Vision is the default and the overwhelming majority of entries: marking those
    /// would put the same word on every row in the list, which is how a label stops being
    /// read. Only the departure from the default carries information.
    static func mark(_ id: String) -> String? {
        id == EngineCatalog.defaultEngineID ? nil : name(id)
    }

    static func megabytes(_ bytes: Int64) -> String {
        String(format: L.s("%d MB"), Int((Double(bytes) / 1_000_000).rounded()))
    }
}
