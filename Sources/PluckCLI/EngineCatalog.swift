import Foundation
import PluckKit

struct EngineDescriptor: Sendable, Equatable {
    let id: String
    let summary: String
    /// Ships with the binary — nothing to download.
    let builtIn: Bool
}

enum EngineCatalog {
    static let defaultEngineID = "vision"

    static let installed: [EngineDescriptor] = [
        EngineDescriptor(
            id: "vision",
            summary: "Apple Vision foreground segmentation (macOS 14+)",
            builtIn: true
        )
    ]

    /// Known to the manifest but not implemented until v0.3.
    static let announced: [String] = ["birefnet-lite"]

    static func descriptor(for id: String) -> EngineDescriptor? {
        installed.first { $0.id == id }
    }

    static func engine(for id: String) -> (any MattingEngine)? {
        switch id {
        case "vision": return VisionEngine()
        default: return nil
        }
    }

    static var availabilityMessage: String {
        let ids = installed.map(\.id).joined(separator: ", ")
        return "available models: \(ids)"
    }
}
