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
/// would be a lie that costs the user the shot they wanted; "Clean Cut" and "Fine Edges"
/// name the two edges themselves, which is the thing being chosen between.
///
/// Nothing here quotes a duration. "~1–2 s" was measured on one machine with one image, and
/// the app repeated it to every user on every Mac as if it were a property of the model. The
/// blurb already carries the whole basis for the choice; a number that is wrong on half the
/// fleet adds nothing to it.
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
        case birefnetLite: L.s("Clean Cut")
        case birefnetLiteMatting: L.s("Fine Edges")
        default: fallback ?? id
        }
    }

    /// One sentence about what comes out, not about what it is made of.
    static func blurb(_ id: String) -> String? {
        switch id {
        case EngineCatalog.defaultEngineID: L.s("Instant, built into macOS.")
        case birefnetLite: L.s("Clean, solid edges — products and objects.")
        case birefnetLiteMatting: L.s("Finer edges — hair, fur, glass.")
        default: nil
        }
    }

    /// The glyph on the row's icon tile (p5). A picture of the *edge* each engine cuts, not
    /// a vendor badge: Apple's logo is a trademark the app has no licence to wear, and a
    /// generic cube for every downloadable model would make the two BiRefNets identical at
    /// the one glance the tile exists for.
    static func symbol(_ id: String) -> String {
        switch id {
        case EngineCatalog.defaultEngineID: "bolt.fill"
        case birefnetLite: "scissors"
        case birefnetLiteMatting: "paintbrush.pointed.fill"
        default: "cube"
        }
    }

    /// How a *result* names the engine that made it, or nil when there is nothing worth
    /// saying. Vision is the default and the overwhelming majority of entries: marking those
    /// would put the same word on every row in the list, which is how a label stops being
    /// read. Only the departure from the default carries information.
    static func mark(_ id: String) -> String? {
        id == EngineCatalog.defaultEngineID ? nil : name(id)
    }

    /// The preview panel's bottom-right corner, in one capsule.
    ///
    /// It used to be two: a provenance pill sitting against the "Cutout" pill, which read as
    /// two labels of equal rank and left "is *Fine Edges* the name of this half, or of the
    /// thing next to it" to be guessed. One capsule has one subject.
    static func cutoutBadge(_ id: String) -> String {
        guard let mark = mark(id) else { return L.s("Cutout") }
        return String(format: L.s("Cutout · %@"), mark)
    }

    static func megabytes(_ bytes: Int64) -> String {
        String(format: L.s("%d MB"), Int((Double(bytes) / 1_000_000).rounded()))
    }
}
