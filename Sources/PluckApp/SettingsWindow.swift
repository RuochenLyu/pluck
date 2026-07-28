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
            // Half of what it used to say — "the only thing it ever downloads is a matting
            // model you ask for by name" — has moved up to the shield line under the model
            // rows, where it is next to the thing it is about. Saying it twice would make
            // both copies read as boilerplate.
            Text(L.s("Your pictures never leave this Mac. Pluck has no account, no telemetry and no uploads."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(width: 480, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The engines, and the choice between them — which are now the same thing.
///
/// There was a `Picker` above this list, repeating in a pop-up menu the names of rows the
/// user could already see. Two controls for one decision, and the one that *made* the
/// decision was the one that showed the least: the picker could not say what an engine was
/// for, and the row that could say it was not clickable. Selecting *is* the row now (p5),
/// which also answers "why is this row here" for Vision — it has nothing to download, and it
/// is still the choice most people are using.
///
/// One row per engine, led by what the thing is *for*. The two BiRefNet models are the same
/// size and the same licence — everything a row could say about them except the one thing
/// that decides which to use, which is that lite cuts a decided edge and lite-matting keeps
/// a soft one (research.md A.6). So the row leads with "Clean Cut" and "Fine Edges" and one
/// sentence about what comes out; `BiRefNet_lite` and its licence sit in the chips, where
/// the people who care about model provenance will still find them.
private struct ModelsSection: View {
    @Bindable var store: ModelStore
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            // No chips-and-blurb caption beyond "Built-in": Vision has no licence to declare
            // and no bytes to warn about, and the blurb already says instant.
            EngineRow(
                id: EngineCatalog.defaultEngineID,
                title: EngineLabels.name(EngineCatalog.defaultEngineID),
                chips: [L.s("Built-in")],
                failure: nil,
                isSelected: preferences.engineID == EngineCatalog.defaultEngineID,
                isSelectable: true,
                select: { preferences.engineID = EngineCatalog.defaultEngineID }
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
        } footer: {
            // The half of the old offline paragraph that is about *models* — said here,
            // against the rows it is about, instead of in a block of small print under the
            // window where it read as a disclaimer.
            Label {
                Text(L.s("Models are downloaded once, stored locally, and never phone home."))
            } icon: {
                Image(systemName: "shield")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }
}

/// The shape every engine row has (p5): the choice, a face, what it is for, and whatever the
/// user can do about it.
private struct EngineRow<Control: View>: View {
    let id: String
    let title: String
    let chips: [String]
    /// Replaces the chips and the blurb when a download has gone wrong — a row that says
    /// "MIT · 83 MB" while the download is broken is answering a question nobody asked.
    let failure: String?
    let isSelected: Bool
    /// False for a model that is not on disk. It cannot be the default engine before it
    /// exists, and a circle that accepts the click and then silently does nothing is worse
    /// than one that is visibly not available yet.
    let isSelectable: Bool
    let select: () -> Void
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: select) {
                SelectionMark(isSelected: isSelected, isEnabled: isSelectable)
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            IconTile(symbol: EngineLabels.symbol(id))

            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                if let failure {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if !chips.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(chips, id: \.self) { Chip(text: $0) }
                        }
                    }
                    if let blurb = EngineLabels.blurb(id) {
                        Text(blurb)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 6)
        // The whole row, not just the 18pt circle: the circle is where the state is shown,
        // and the name and the sentence beside it are what the user is actually reading when
        // they decide.
        .contentShape(Rectangle())
        .onTapGesture { if isSelectable { select() } }
    }
}

/// Coral, and the only tinted thing in this window (§4.7): the default engine is the one
/// fact the pane exists to state.
private struct SelectionMark: View {
    let isSelected: Bool
    let isEnabled: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(Palette.coral)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(.tertiary, lineWidth: 1)
            }
        }
        .frame(width: 18, height: 18)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityHidden(true)
    }
}

/// A face for the row, in place of the vendor logos p5 draws: Apple's mark is a trademark
/// this app has no licence to wear, and BiRefNet has no mark at all. A tinted glyph of the
/// *edge* each engine cuts does the same job — something for the eye to land on — without
/// borrowing anyone's identity.
private struct IconTile: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary.opacity(0.6))
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
    }
}

/// The technical identity of a row, in the order someone reads it: the model's real name,
/// then its licence and its size. Small enough to be skipped by everyone it is not for.
private struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.6), in: Capsule())
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
            chips: [
                row.descriptor.displayName,
                "\(row.descriptor.license) · \(EngineLabels.megabytes(row.descriptor.bytes))"
            ],
            failure: failure,
            isSelected: preferences.engineID == row.id,
            isSelectable: row.isInstalled,
            select: { preferences.engineID = row.id }
        ) {
            control
        }
    }

    private var failure: String? {
        if case .failed(let reason) = row.state { return reason }
        return nil
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
            // No "installed" tick beside Delete. The row offering Delete *is* the statement
            // that it is here, and the selection circle beside it is now live — two more
            // signals than the tick was carrying on its own.
            Button(L.s("Delete")) { store.delete(row.id, preferences: preferences) }
        case .available, .failed:
            Button(L.s("Download")) { store.download(row.id) }
        }
    }
}
