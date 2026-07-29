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

    func show(model: AppModel, preferences: Preferences, updates: UpdateController) {
        if window == nil {
            let window = make(model: model, preferences: preferences, updates: updates)
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

    /// The `Form` inside redraws itself — its bodies call `L.s`, which is observable. What
    /// does not is the title bar, and the window's height, which was measured from the
    /// English layout at birth: Chinese sets the same paragraphs in fewer lines, and a
    /// window that keeps the old height would leave a band of empty glass under the last
    /// sentence.
    func languageDidChange() {
        guard let window else { return }
        window.title = L.s("Pluck Settings")
        // One turn later, and then a forced layout: observation schedules SwiftUI's update
        // rather than performing it, so a `fittingSize` read inside the notification would
        // measure the sentences the window is about to stop showing.
        Task { @MainActor in
            guard let hosting = window.contentView else { return }
            hosting.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.fittingSize)
        }
    }

    private func make(model: AppModel, preferences: Preferences, updates: UpdateController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L.s("Pluck Settings")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: SettingsView(model: model, preferences: preferences, updates: updates)
        )
        window.contentView = hosting
        // The pane's height is whatever three sections of text come to; guessing it in the
        // contentRect above would either clip the offline statement or leave a gap under it.
        window.setContentSize(hosting.fittingSize)
        return window
    }
}

/// One scrolling pane, a handful of sections. Still not the tabbed toolbar §4.7 sketched:
/// sections that fit on one screen do not need a toolbar to switch between them, and a tab
/// bar over three tabs is chrome that exists to look like other apps' chrome.
///
/// Visual language v2's "no hairlines" rule stops at this window's door, and deliberately.
/// §4.7 grades the glass by surface: the panels are ours to draw, but Settings is a window
/// the user goes *looking* for, and it should look like every other Settings window on the
/// machine. So the grouped `Form` keeps its own boxes and whatever separators AppKit draws
/// between rows — those are not ours to remove without reimplementing the form, which would
/// trade the native thing the user came here to find for a house style.
/// The rows *inside* it are ours, and those follow v2.
struct SettingsView: View {
    let model: AppModel
    @Bindable var preferences: Preferences
    let updates: UpdateController
    @State private var models: ModelStore

    init(
        model: AppModel,
        preferences: Preferences,
        updates: UpdateController,
        models: ModelStore = ModelStore()
    ) {
        self.model = model
        self.preferences = preferences
        self.updates = updates
        _models = State(initialValue: models)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                LanguageSection(preferences: preferences)

                ModelsSection(store: models, preferences: preferences)

                Section {
                    // The label is a `Text` of its own so it can be told to wrap. A
                    // `Toggle(_:isOn:)` with a string title truncates it instead, and the
                    // switch stays pinned to the trailing edge of a 480pt form — so the
                    // first language whose sentence is longer than English's loses the end
                    // of the only sentence that says what the switch does.
                    Toggle(isOn: $preferences.keepsHistory) {
                        Text(L.s("Keep recent cutouts between launches"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .onChange(of: preferences.keepsHistory) { _, keeps in
                        guard !keeps else { return }
                        model.forgetStoredHistory()
                    }
                    // One sentence, in the user's vocabulary. "Application Support" is a
                    // directory name from a developer's mental model of the machine, and
                    // "never uploaded" was the third statement of the privacy claim in a
                    // window 300pt tall — the line at the bottom says it best and says it
                    // once.
                    Text(L.s("Kept only on this Mac. Turn this off and cutouts are forgotten when you quit."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // The same button as the ones on the engine rows. Left stock, it was the
                    // one flat grey control in a window whose other buttons had become glass —
                    // two vocabularies in one pane, which is worse than either alone.
                    RowButton(L.s("Clear recent cutouts")) { model.clearRecents() }
                        .disabled(model.recents.items.isEmpty)
                } header: {
                    Text(L.s("History")).font(.headline)
                }

                UpdatesSection(preferences: preferences, updates: updates)
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            // Not a boast — it is the one claim the whole product rests on, and the place a
            // doubting user looks first is Settings. Out of the grouped box it used to sit
            // in: a boxed row reads as a setting, and this is a statement about the app.
            //
            // The *only* place it is made. There were three: a shield row under the model
            // list ("stored locally, and never phone home"), a clause in the history blurb
            // ("and never uploaded"), and this. Three statements of one promise do not add up
            // to three times the credibility — they read as a disclaimer, which is what small
            // print about privacy looks like when it is repeated. This is the widest of the
            // three, so it is the one that stays.
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

/// The only place in this window that admits to a network connection Pluck makes on its own.
///
/// Last section, and phrased as plainly as the offline claim two lines below it. A privacy
/// promise with one exception in it is only worth what the exception's disclosure is worth:
/// the sentence says who is contacted (GitHub), how often (daily), what is asked (whether
/// there is a newer version), and what turning the switch off buys (nothing is contacted).
/// That is the whole of it, and it is short enough that nobody has to take it on faith.
///
/// The version number lives here rather than only in About because it is the number the
/// button beside it is about to compare against a server — "Check Now" answering "you're up
/// to date" means more next to the version it is up to date at.
private struct UpdatesSection: View {
    @Bindable var preferences: Preferences
    let updates: UpdateController

    var body: some View {
        Section {
            // Same `Text` treatment as the history switch: a `Toggle` with a string title
            // truncates rather than wraps, and this label is longer in some languages than
            // in English.
            Toggle(isOn: $preferences.checksForUpdates) {
                Text(L.s("Check for updates automatically"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: preferences.checksForUpdates) { _, on in
                updates.setAutomaticChecks(on)
            }
            .disabled(!updates.isAvailable)

            Text(L.s("Once a day, Pluck asks GitHub whether a newer version exists. Nothing about you or your pictures is sent. Turn this off and Pluck never connects on its own."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                RowButton(L.s("Check Now")) { updates.checkNow() }
                    .disabled(!updates.isAvailable)
                if let version = AppVersion.display() {
                    // Verbatim: `AppVersion.display` has already been through the catalog,
                    // and running its result through a second lookup would ask for a key
                    // that reads "Version 0.1.0".
                    Text(verbatim: version)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Said out loud rather than hidden, because the state is otherwise invisible: a
            // disabled switch with no explanation reads as a bug. This is what every build
            // made from source looks like — the signing key is the maintainer's, and it is
            // not in the repository.
            if !updates.isAvailable {
                Text(L.s("This build carries no update signing key, so it cannot check for updates."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(L.s("Updates")).font(.headline)
        }
    }
}

/// One row, at the top, because it decides how every other row in the window reads.
///
/// Each option is written in the language it selects: "English" is always English and
/// "简体中文" is always 简体中文, no matter what the app is currently speaking. This is the
/// convention every language picker on every platform follows, and the reason is that the
/// person who needs this control is by definition someone the current language is failing.
/// A menu that says "Chinese, Simplified" to a user who cannot read English is a menu that
/// only works for people who did not need it. Only "System" is translated — it names a
/// behaviour rather than a language, and the person reading it can read what is around it.
///
/// So the two language names are `Text(verbatim:)` and appear in no catalog: they are not
/// copy, and a translator who "improved" them would break the control.
private struct LanguageSection: View {
    @Bindable var preferences: Preferences

    /// A labelled row, not a headed section. The other two sections are headed because each
    /// is a list of things with a sentence about them; this is one pop-up menu, and a
    /// `Language` header over a row whose label would also read `Language` is the word twice.
    var body: some View {
        Section {
            Picker(selection: $preferences.languageID) {
                Text(L.s("System")).tag(L.systemID)
                Text(verbatim: "English").tag("en")
                Text(verbatim: "简体中文").tag("zh-Hans")
            } label: {
                Text(L.s("Language"))
            }
            .pickerStyle(.menu)
        }
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
/// sentence about what comes out; `BiRefNet_lite`, its licence and its size sit on one small
/// tertiary line under the name, where the people who care about model provenance will still
/// find them and nobody else has to.
private struct ModelsSection: View {
    @Bindable var store: ModelStore
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            // No caption at all: Vision has no licence to declare and no bytes to warn
            // about, and its blurb already says it is built into macOS — a "Built-in" chip
            // above that sentence was the sentence again, in a pill.
            EngineRow(
                id: EngineCatalog.defaultEngineID,
                title: EngineLabels.name(EngineCatalog.defaultEngineID),
                detail: nil,
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
        }
    }
}

/// The shape every engine row has (p5): the choice, a face, what it is for, and whatever the
/// user can do about it.
private struct EngineRow<Control: View>: View {
    let id: String
    let title: String
    /// The model's technical identity, on one line: real name, licence, size. It was three
    /// pilled chips, which gave a row four competing type sizes and drew a lot of furniture
    /// around the one part of it written for the few people who care about provenance. Small,
    /// tertiary, unpilled — skippable by everyone it is not for, which is what it was for.
    let detail: String?
    /// Replaces the detail line and the blurb when a download has gone wrong — a row that
    /// says "MIT · 83 MB" while the download is broken is answering a question nobody asked.
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

            IconTile(symbol: EngineLabels.symbol(id), isSelected: isSelected)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let failure {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if let detail {
                        // Verbatim: it is a model id, a licence and a byte count, none of
                        // which are prose and none of which are in the catalog.
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
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
        .padding(.vertical, 8)
        // The whole row, not just the 22pt circle: the circle is where the state is shown,
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(.tertiary, lineWidth: 1)
            }
        }
        .frame(width: 22, height: 22)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityHidden(true)
    }
}

/// A face for the row, in place of the vendor logos p5 draws: Apple's mark is a trademark
/// this app has no licence to wear, and BiRefNet has no mark at all. A tinted glyph of the
/// *edge* each engine cuts does the same job — something for the eye to land on — without
/// borrowing anyone's identity.
///
/// The tile is washed with coral at 8→16%, and the selected row's glyph is coral outright.
/// This does not spend the one-tint-per-screen budget (§4.7): an 8% diagonal wash is a
/// surface tint, the way a Dropover tile is a surface, and the countable *tinted element*
/// in this window is still the selection mark. What the wash buys is a column of tiles that
/// belongs to Pluck rather than three grey squares that could be from any preferences pane.
private struct IconTile: View {
    let symbol: String
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Palette.coral.opacity(0.08), Palette.coral.opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Palette.coral) : AnyShapeStyle(.secondary))
            }
            .accessibilityHidden(true)
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
            detail: "\(row.descriptor.displayName) · \(row.descriptor.license) · \(EngineLabels.megabytes(row.descriptor.bytes))",
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
                RowButton(L.s("Cancel")) { store.cancel(row.id) }
            }
        case .installed:
            // No "installed" tick beside Delete. The row offering Delete *is* the statement
            // that it is here, and the selection circle beside it is now live — two more
            // signals than the tick was carrying on its own.
            RowButton(L.s("Delete")) { store.delete(row.id, preferences: preferences) }
        case .available, .failed:
            RowButton(L.s("Download")) { store.download(row.id) }
        }
    }
}

/// The one place glass gets into Settings.
///
/// The window itself stays native — §4.7 grades the glass by surface, and Settings is a
/// window the user goes *looking* for, so its `Form`, its grouped boxes and the separators
/// AppKit draws between rows are not ours to replace with a house style. But the trailing
/// control on an engine row is ours, and on macOS 26 `.glass` is simply what a secondary
/// button in a list looks like now — leaving it `.bordered` would make this the one window in
/// the app still wearing the old control, which is the opposite of what "native" was for.
private struct RowButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            Button(title, action: action).buttonStyle(.glass)
        } else {
            Button(title, action: action)
        }
    }
}
