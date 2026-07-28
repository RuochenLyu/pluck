import AppKit
import PluckKit
import SwiftUI

/// The first surface in Pluck with a system title bar, and deliberately so: §4.7's
/// borderless-glass rules are about panels that hang off the menu bar and stand in front
/// of the user's work. Settings is a window the user goes looking for, opens once, and
/// closes — it should look like every other Settings window on the machine.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(model: AppModel, preferences: Preferences) {
        if window == nil {
            let window = make(model: model, preferences: preferences)
            // Centred once, at birth. Re-centring on every open would undo the user's own
            // placement, which is the one thing a window that is opened repeatedly must not do.
            window.center()
            self.window = window
        }
        // An accessory app is not frontmost by default, so both halves are needed: activate
        // the process, then raise the window inside it.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func make(model: AppModel, preferences: Preferences) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L.s("Pluck Settings")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: SettingsView(model: model, preferences: preferences))
        window.contentView = hosting
        // The pane's height is whatever three sections of text come to; guessing it in the
        // contentRect above would either clip the offline statement or leave a gap under it.
        window.setContentSize(hosting.fittingSize)
        return window
    }
}

/// One scrolling pane, two sections. Still not the tabbed toolbar §4.7 sketched: two
/// sections that fit on one screen do not need a toolbar to switch between them, and a tab
/// bar over two tabs is chrome that exists to look like other apps' chrome.
struct SettingsView: View {
    let model: AppModel
    @Bindable var preferences: Preferences
    @State private var models: ModelStore

    init(model: AppModel, preferences: Preferences, models: ModelStore = ModelStore()) {
        self.model = model
        self.preferences = preferences
        _models = State(initialValue: models)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                ModelsSection(store: models, preferences: preferences)

                Section {
                    Toggle(L.s("Keep recent cutouts between launches"), isOn: $preferences.keepsHistory)
                        .onChange(of: preferences.keepsHistory) { _, keeps in
                            guard !keeps else { return }
                            model.forgetStoredHistory()
                        }
                    Text(L.s("Stored on this Mac in Application Support, and never uploaded. Turn this off and cutouts are kept only until you quit."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L.s("Clear recent cutouts")) { model.clearRecents() }
                        .disabled(model.recents.items.isEmpty)
                } header: {
                    Text(L.s("History")).font(.headline)
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            // Not a boast — it is the one claim the whole product rests on, and the place a
            // doubting user looks first is Settings. Out of the grouped box it used to sit
            // in: a boxed row reads as a setting, and this is a statement about the app.
            //
            // Amended in v0.3 rather than quietly left standing: models are downloaded, so
            // "makes no network requests" had stopped being true. The claim that matters —
            // pictures never leave the Mac — is unchanged, and stating the one exception is
            // what makes the rest believable.
            Text(L.s("Your pictures never leave this Mac. Pluck has no account, no telemetry and no uploads; the only thing it ever downloads is a matting model you ask for by name."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(width: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The engine picker and the engines it picks from.
///
/// One row per engine, led by what the thing is *for*. The two BiRefNet models are the same
/// size, the same speed and the same licence — everything a row could say about them except
/// the one thing that decides which to use, which is that lite cuts a decided edge and
/// lite-matting keeps a soft one (research.md A.6). So the row leads with "Detail" and
/// "Matting" and one sentence about what comes out; `BiRefNet_lite` and its licence drop to
/// the caption, where the people who care about model provenance will still find them.
///
/// Vision is in the list too, without a control. It is not downloadable, so it used to be
/// invisible here — which left the pane describing the two choices the user has to *make*
/// and not the one they already have.
private struct ModelsSection: View {
    @Bindable var store: ModelStore
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            Picker(L.s("Engine"), selection: $preferences.engineID) {
                Text(EngineLabels.name(EngineCatalog.defaultEngineID)).tag(EngineCatalog.defaultEngineID)
                ForEach(store.rows.filter(\.isInstalled)) { row in
                    Text(EngineLabels.name(row.id, fallback: row.descriptor.displayName)).tag(row.id)
                }
            }

            EngineRow(
                id: EngineCatalog.defaultEngineID,
                title: EngineLabels.name(EngineCatalog.defaultEngineID),
                caption: String(
                    format: L.s("%1$@ · %2$@"),
                    L.s("Built into macOS"),
                    EngineLabels.paceDetail(EngineCatalog.defaultEngineID)
                ),
                captionIsFailure: false
            ) {}

            if store.registry == nil {
                Text(L.s("This build carries no model list."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.rows) { row in
                ModelRowView(row: row, store: store, preferences: preferences)
            }
        } header: {
            Text(L.s("Models")).font(.headline)
        }
    }
}

/// The shape every engine row has: what it is for, then what it is made of, then whatever
/// the user can do about it.
private struct EngineRow<Control: View>: View {
    let id: String
    let title: String
    let caption: String
    let captionIsFailure: Bool
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let blurb = EngineLabels.blurb(id) {
                    Text(blurb)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(captionIsFailure ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.vertical, 2)
    }
}

private struct ModelRowView: View {
    let row: ModelRow
    let store: ModelStore
    let preferences: Preferences

    var body: some View {
        EngineRow(
            id: row.id,
            title: EngineLabels.name(row.id, fallback: row.descriptor.displayName),
            caption: caption,
            captionIsFailure: isFailed
        ) {
            control
        }
    }

    /// The technical identity of the row, in the order someone reads it: the model's real
    /// name, its licence, its size, its speed. A failure replaces the lot — a row that says
    /// "83 MB · MIT" while the download is broken is answering a question nobody asked.
    private var caption: String {
        if case .failed(let reason) = row.state { return reason }
        return [
            row.descriptor.displayName,
            row.descriptor.license,
            EngineLabels.megabytes(row.descriptor.bytes),
            EngineLabels.paceDetail(row.id)
        ].joined(separator: " · ")
    }

    private var isFailed: Bool {
        if case .failed = row.state { return true }
        return false
    }

    @ViewBuilder private var control: some View {
        switch row.state {
        case .downloading(let fraction):
            HStack(spacing: 8) {
                // Determinate wherever the manifest's byte count allows it, which is
                // always: a 94 MB download behind a barber's pole is indistinguishable
                // from a stalled one.
                ProgressView(value: fraction ?? 0, total: 1)
                    .progressViewStyle(.linear)
                    .frame(width: 90)
                Button(L.s("Cancel")) { store.cancel(row.id) }
            }
        case .installed:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L.s("Installed"))
                Button(L.s("Delete")) { store.delete(row.id, preferences: preferences) }
            }
        case .available, .failed:
            Button(L.s("Download")) { store.download(row.id) }
        }
    }
}
