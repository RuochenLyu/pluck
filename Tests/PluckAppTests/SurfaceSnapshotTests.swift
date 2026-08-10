import AppKit
import PluckKit
import SwiftUI
import XCTest

@testable import PluckApp

/// Renders each of the app's three SwiftUI surfaces and checks it drew something.
///
/// Two jobs. The assertion is the cheap one and it is still worth having: a surface whose
/// body throws, lays out to zero, or renders blank is a failure no other test in this suite
/// notices, because every one of them tests a rule rather than a picture.
///
/// The other job is the reason it exists. This project's own history says screenshot review
/// catches things reading the code does not (decisions.md 2026-07-28, the engine chip that
/// rendered as a bare caption on macOS 26) — and on a machine where `screencapture` is not
/// permitted, this is the only way to get an image of a surface out of the app. Set
/// `PLUCK_SNAPSHOT_DIR` and each surface is written there as a PNG.
///
/// Rendered through `NSHostingView.cacheDisplay` rather than through `ImageRenderer`, and
/// that is not a preference: `ImageRenderer` returns a **fully transparent** image for any
/// hierarchy containing `.glassEffect` or `.buttonStyle(.glass)` — measured on this machine,
/// and it takes the whole tree with it, not just the glass. Every surface in this app has
/// glass in it, so `ImageRenderer` would have rendered five blank rectangles and asserted
/// happily that they were the right size.
///
/// What `cacheDisplay` still cannot show is the glass *substance*: it is composited by the
/// window server, outside the layer tree, so it comes out transparent here. Everything drawn
/// on top of it — every card, word, glyph and control — is present, which is what makes this
/// useful for the thing it is for: spacing, rhythm, wrapping and whether a control is where
/// it was meant to be. The backdrop's own correctness is `PanelBackdropTests`' subject, and
/// that one is asserted pixel by pixel rather than looked at.
@MainActor
final class SurfaceSnapshotTests: XCTestCase {
    private var model: AppModel!
    private var preferences: Preferences!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "PluckSnapshotTest-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        preferences = Preferences(defaults: defaults)
        model = AppModel()
        model.recents.restore((0..<5).map { index in
            RecentItem(
                fingerprint: "f\(index)",
                thumbnailPNG: Self.swatch(index),
                fileURL: URL(fileURLWithPath: "/tmp/pluck-snapshot/\(index)/IMG_004\(index).png"),
                originalURL: URL(fileURLWithPath: "/tmp/pluck-snapshot/\(index)/original.png"),
                suggestedName: "IMG_004\(index)",
                pixelWidth: 1200,
                pixelHeight: 800
            )
        })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// A recognisable block of colour, so a snapshot shows cards with something in them
    /// rather than five empty mounts.
    private static func swatch(_ index: Int) -> Data {
        let size = NSSize(width: 60, height: 40)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(hue: CGFloat(index) / 5, saturation: 0.55, brightness: 0.9, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return Data() }
        return png
    }

    private func snapshot(_ name: String, width: CGFloat, height: CGFloat?, _ view: some View) throws {
        let host = NSHostingView(rootView: AnyView(view.frame(width: width).frame(height: height)))
        // Light, because that is what the maintainer reviews these in; the dark half is the
        // checkerboard's business and `CheckerboardTests` already holds both ends of it.
        host.appearance = NSAppearance(named: .aqua)
        let size = host.fittingSize
        XCTAssertGreaterThan(size.width, 0, "\(name) laid out to zero width")
        XCTAssertGreaterThan(size.height, 0, "\(name) laid out to zero height")
        host.frame = NSRect(origin: .zero, size: size)

        // A real window, offscreen. Materials, control tints and effect views all ask the
        // window they are in what they should look like, and a view with no window answers
        // those questions with defaults.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)

        // Something was drawn. Blank is the failure this test exists to catch — it is what
        // `ImageRenderer` produced for every one of these surfaces, silently.
        var ink = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) where
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                ink += 1
            }
        }
        XCTAssertGreaterThan(ink, 0, "\(name) drew nothing at all")

        guard let directory = ProcessInfo.processInfo.environment["PLUCK_SNAPSHOT_DIR"] else { return }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

    func testTheMainWindowDraws() throws {
        try snapshot(
            "dk-main-window",
            width: 620,
            height: 540,
            MainWindowView(model: model, dropTarget: DropTarget())
        )
    }

    /// With one cutout selected, so the bar is showing Deselect All and "Export 1…" — the
    /// two labels that change with the state.
    func testTheMainWindowDrawsWithASelection() throws {
        model.select(model.recents.items[1])
        try snapshot(
            "dk-main-window-selected",
            width: 620,
            height: 540,
            MainWindowView(model: model, dropTarget: DropTarget())
        )
    }

    func testTheEmptyMainWindowDraws() throws {
        try snapshot(
            "dk-main-window-empty",
            width: 620,
            height: 540,
            MainWindowView(model: AppModel(), dropTarget: DropTarget())
        )
    }

    /// Height is the form's own — Settings is sized to `fittingSize` at birth, so a fixed
    /// frame here would snapshot a window shape the app never puts on screen.
    func testSettingsDraws() throws {
        try snapshot(
            "dk-settings",
            width: 480,
            height: nil,
            GeneralPane(model: model, preferences: preferences, updates: UpdateController())
        )
    }

    /// The inspector, pointed at a real cutout: the comparison box, the details and the
    /// action row are the redesign's centrepiece.
    func testThePreviewInspectorDraws() throws {
        model.preview(model.recents.items[0])
        try snapshot(
            "dk-inspector",
            width: 340,
            height: 520,
            PreviewInspectorView(model: model)
        )
    }

    /// The same pane with a manifest behind it, which is the only way to see the part of it
    /// that was rebuilt: the model rows. A build with no manifest — which is what a test
    /// bundle is — renders the "no model list" sentence and nothing else, so the section
    /// this change is mostly about would go unlooked-at.
    func testSettingsDrawsTheModelRows() throws {
        let manifest = try ModelManifest(data: Data("""
            {
              "version": 1,
              "models": [{
                "id": "birefnet-lite",
                "displayName": "BiRefNet_lite",
                "file": "BiRefNet_lite.mlpackage",
                "url": "https://example.invalid/a.zip",
                "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
                "bytes": 83000000,
                "license": "MIT",
                "source": "https://example.invalid/a",
                "inputSide": 1024
              }, {
                "id": "birefnet-lite-matting",
                "displayName": "BiRefNet_lite matting",
                "file": "BiRefNet_lite_matting.mlpackage",
                "url": "https://example.invalid/b.zip",
                "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
                "bytes": 83000000,
                "license": "MIT",
                "source": "https://example.invalid/b",
                "inputSide": 1024
              }]
            }
            """.utf8))
        let registry = ModelRegistry(
            manifest: manifest,
            root: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pluck-snapshot-models")
        )
        try snapshot(
            "dk-settings-models",
            width: 480,
            height: nil,
            ModelsForm(
                store: ModelStore(registry: registry, engines: EngineProvider(catalog: EngineCatalog(registry: nil))),
                preferences: preferences
            )
        )
    }
}
