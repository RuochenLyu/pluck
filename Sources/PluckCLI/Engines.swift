import Foundation
import PluckKit

/// The CLI's copy of the catalog. The engine list itself moved to PluckKit in v0.3 so the
/// app could ask the same question; what stays here is only *which* manifest to ask about —
/// the one compiled into this binary as a resource (`Sources/PluckCLI/Resources`), never one
/// found next to the working directory.
enum Engines {
    static let catalog = EngineCatalog.bundled(in: .module)

    static var defaultEngineID: String { EngineCatalog.defaultEngineID }
}
