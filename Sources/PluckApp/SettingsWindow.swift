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
                GeneralSection(preferences: preferences)

                ModelsSection(store: models, preferences: preferences)

                HistorySection(model: model, preferences: preferences)

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

/// What Pluck is keeping, and what it costs.
///
/// The size on the Clear button is the whole reason this section is not just a switch: an
/// archive of everything the user has ever plucked grows without anyone watching it, and
/// "Clear recent cutouts" with no number beside it is a button nobody presses because nobody
/// knows whether it is worth pressing. Measured off the main actor, and *not* shown when it
/// rounds to zero — see `EngineLabels.megabytes(orNothing:)`.
///
/// The safety-net sentence is stated only for kept history, and only because it is true
/// there: `CutoutArchive.discard` trashes entries under the history root and deletes session
/// ones outright, which is right — session files are temporary by the user's own instruction.
/// A blanket "you can get them back" would be a promise the session case does not keep.
private struct HistorySection: View {
    let model: AppModel
    @Bindable var preferences: Preferences

    /// Nil until the walk finishes, and again the moment the grid changes — the number is
    /// re-measured rather than adjusted, because a running total is one more thing that can
    /// drift out of agreement with the disk.
    @State private var bytes: Int64?

    private var clearTitle: String {
        guard let size = bytes.flatMap(EngineLabels.megabytes(orNothing:)) else {
            return L.s("Clear recent cutouts")
        }
        return String(format: L.s("Clear recent cutouts (%@)"), size)
    }

    var body: some View {
        Section {
            // The label is a `Text` of its own so it can be told to wrap. A
            // `Toggle(_:isOn:)` with a string title truncates it instead, and the switch
            // stays pinned to the trailing edge of a 480pt form — so the first language
            // whose sentence is longer than English's loses the end of the only sentence
            // that says what the switch does.
            Toggle(isOn: $preferences.keepsHistory) {
                Text(L.s("Keep recent cutouts between launches"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: preferences.keepsHistory) { _, keeps in
                guard !keeps else { return }
                model.forgetStoredHistory()
            }
            // One sentence, in the user's vocabulary. "Application Support" is a directory
            // name from a developer's mental model of the machine, and "never uploaded" was
            // the third statement of the privacy claim in a window 300pt tall — the line at
            // the bottom says it best and says it once.
            Text(L.s("Kept only on this Mac. Turn this off and cutouts are forgotten when you quit."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if preferences.keepsHistory {
                Text(L.s("Clearing puts them in the Trash, the same as deleting one from the grid."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The same button as the ones on the model rows. Left stock, it was the one flat
            // grey control in a window whose other buttons had become glass — two
            // vocabularies in one pane, which is worse than either alone.
            RowButton(clearTitle) { model.clearRecents() }
                .disabled(model.recents.items.isEmpty)
        } header: {
            Text(L.s("History")).font(.headline)
        }
        // Re-measured whenever the grid changes size, which covers both directions: a batch
        // landing and the Clear this very button just performed.
        .task(id: model.recents.items.count) {
            let archive = preferences.archive
            bytes = await Task.detached(priority: .utility) { archive.totalBytes() }.value
        }
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

/// Where Pluck shows up, and what language it does it in — the section that decides how
/// every other row in the window reads, so it comes first.
///
/// The two presence switches are one decision in two halves and are written as such: the
/// Dock switch is disabled while the menu bar icon is off, because with neither there would
/// be nothing on screen to click. `Preferences` enforces that as an invariant rather than
/// this view enforcing it as a disabled control — a rule that only exists in a `.disabled`
/// modifier is a rule the next surface to touch these booleans will not have.
///
/// Each language option is written in the language it selects: "English" is always English
/// and "简体中文" is always 简体中文, no matter what the app is currently speaking. This is
/// the convention every language picker on every platform follows, and the reason is that
/// the person who needs this control is by definition someone the current language is
/// failing. A menu that says "Chinese, Simplified" to a user who cannot read English is a
/// menu that only works for people who did not need it. Only "System" is translated — it
/// names a behaviour rather than a language, and the person reading it can read what is
/// around it. So the two language names are `Text(verbatim:)` and appear in no catalog:
/// they are not copy, and a translator who "improved" them would break the control.
private struct GeneralSection: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            Toggle(isOn: $preferences.showsMenuBarIcon) {
                Text(L.s("Show Pluck in the menu bar"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $preferences.hidesDockIcon) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.s("Hide the Dock icon"))
                        .fixedSize(horizontal: false, vertical: true)
                    if !preferences.canHideDockIcon {
                        // Said out loud, because a control that is grey for a reason the user
                        // cannot see reads as a broken control rather than as an unavailable
                        // one.
                        Text(L.s("Needs the menu bar icon — otherwise there would be nowhere left to click."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .disabled(!preferences.canHideDockIcon)

            Picker(selection: $preferences.languageID) {
                Text(L.s("System")).tag(L.systemID)
                Text(verbatim: "English").tag("en")
                Text(verbatim: "简体中文").tag("zh-Hans")
            } label: {
                Text(L.s("Language"))
            }
            .pickerStyle(.menu)
        } header: {
            Text(L.s("General")).font(.headline)
        }
    }
}

/// The default engine, and the models that can be one.
///
/// Those are two different questions and they are now asked separately. They used to be the
/// same control: every row carried a selection circle, so the list was simultaneously "which
/// engine do new pictures go through" and "what is on this disk". That reads fine with two
/// rows and stops working the moment a model is downloading, or failed, or not installed —
/// a circle that is greyed because the bytes have not arrived is answering a question about
/// downloads in the vocabulary of a preference.
///
/// So: one pop-up at the top that states the preference in a sentence ("New images use …"),
/// listing only engines that can actually serve it, and below it a plain management list.
/// Each row is five things and no more — tile, name, one sentence about what comes out, one
/// small line of provenance, and the button that changes its state — which is the same
/// breathing room the History section has.
///
/// The rows lead with what the thing is *for*. The two BiRefNet models are the same size and
/// the same licence, so everything a row could say about them is identical except the one
/// thing that decides which to use: lite cuts a decided edge, lite-matting keeps a soft one
/// (research.md A.6). Hence "Clean Cut" and "Fine Edges", with `BiRefNet_lite`, its licence
/// and its weight on one tertiary line where people who care about provenance will find them
/// and nobody else has to.
private struct ModelsSection: View {
    @Bindable var store: ModelStore
    @Bindable var preferences: Preferences

    /// Everything that could be the default right now: Vision, which is always here, plus
    /// whatever is on disk.
    private var choices: [String] {
        [EngineCatalog.defaultEngineID] + store.rows.filter(\.isInstalled).map(\.id)
    }

    /// Reads through the same fallback the pipeline uses rather than writing it back.
    /// `Preferences.engineID` deliberately keeps pointing at a model that has been deleted —
    /// a preference that quietly rewrites itself is worse than one that is briefly
    /// unsatisfiable — so the pop-up shows what today's drop would actually use, and only a
    /// deliberate choice stores anything.
    private var selection: Binding<String> {
        Binding(
            get: { choices.contains(preferences.engineID) ? preferences.engineID : EngineCatalog.defaultEngineID },
            set: { preferences.engineID = $0 }
        )
    }

    var body: some View {
        Section {
            Picker(selection: selection) {
                ForEach(choices, id: \.self) { id in
                    Text(EngineLabels.name(id, fallback: store.rows.first { $0.id == id }?.descriptor.displayName))
                        .tag(id)
                }
            } label: {
                Text(L.s("New images use"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .pickerStyle(.menu)

            if store.registry == nil {
                Text(L.s("This build carries no model list."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            // No row for Vision down here any more. It exists to be *chosen*, and the pop-up
            // above is where choosing happens; a row offering no Download and no Delete would
            // be a line of furniture in a list whose whole subject is bytes on disk.
            ForEach(store.rows) { row in
                ModelRowView(row: row, store: store, preferences: preferences)
            }
        } header: {
            Text(L.s("Models")).font(.headline)
        }
        .task { await store.measureInstalled() }
    }
}

/// The shape every model row has: a face, what it is for, what it is, and the one button that
/// changes its state.
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
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: EngineLabels.symbol(id))

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
                    if let blurb = EngineLabels.blurb(id) {
                        Text(blurb)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let detail {
                        // Verbatim: it is a model id, a licence and a byte count, none of
                        // which are prose and none of which are in the catalog.
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 8)
    }
}

/// A face for the row, in place of the vendor logos p5 draws: Apple's mark is a trademark
/// this app has no licence to wear, and BiRefNet has no mark at all. A tinted glyph of the
/// *edge* each engine cuts does the same job — something for the eye to land on — without
/// borrowing anyone's identity.
///
/// The tile is washed with coral at 8→16%. This does not spend the one-tint-per-screen
/// budget (§4.7): an 8% diagonal wash is a surface tint, the way a Dropover tile is a
/// surface. What it buys is a column of tiles that belongs to Pluck rather than three grey
/// squares that could be from any preferences pane.
private struct IconTile: View {
    let symbol: String

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
                    .foregroundStyle(.secondary)
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
            detail: row.detail,
            failure: failure
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
