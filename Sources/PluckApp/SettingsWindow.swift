import AppKit
import PluckKit
import SwiftUI

/// A standard toolbar-tab Settings window — the shape every Mac settings window has, built
/// with `NSTabViewController(.toolbar)` so the tabs, the transition and the per-pane window
/// sizing are all the system's.
///
/// Two panes. General is the app's behaviour (language, history, the one network switch);
/// Models is the product's core choice and gets a pane of its own — the model list is a
/// selling point, not a preference to bury.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var tabs: SettingsTabsController?

    func show(model: AppModel, preferences: Preferences, updates: UpdateController) {
        if window == nil {
            let tabs = SettingsTabsController(model: model, preferences: preferences, updates: updates)
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.title = tabs.selectedLabel
            window.isReleasedWhenClosed = false
            window.center()
            self.tabs = tabs
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// The SwiftUI panes redraw themselves — their bodies call `L.s`, which is observable.
    /// The tab labels and the window title are AppKit copies and have to be replaced.
    func languageDidChange() {
        guard let tabs, let window else { return }
        tabs.relabel()
        window.title = tabs.selectedLabel
    }
}

/// The tab controller, subclassed for the two facts AppKit does not handle by itself: the
/// window title follows the selected tab (System Settings behaviour), and the labels are
/// rebuilt on a language switch.
final class SettingsTabsController: NSTabViewController {
    init(model: AppModel, preferences: Preferences, updates: UpdateController) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar

        let general = NSHostingController(
            rootView: GeneralPane(model: model, preferences: preferences, updates: updates)
        )
        general.sizingOptions = .preferredContentSize
        let generalItem = NSTabViewItem(viewController: general)
        generalItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)

        let models = NSHostingController(rootView: ModelsPane(preferences: preferences))
        models.sizingOptions = .preferredContentSize
        let modelsItem = NSTabViewItem(viewController: models)
        modelsItem.image = NSImage(systemSymbolName: "square.3.layers.3d", accessibilityDescription: nil)

        addTabViewItem(generalItem)
        addTabViewItem(modelsItem)
        relabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    var selectedLabel: String {
        let index = max(0, selectedTabViewItemIndex)
        return tabViewItems.indices.contains(index) ? tabViewItems[index].label : L.s("Pluck Settings")
    }

    /// The window title rides on the child view controllers' `title`, because that is what
    /// `NSTabViewController` propagates on every selection change — a title written straight
    /// to the window here would be overwritten with "Untitled" (a hosting controller's nil
    /// title) the moment the user switches tabs.
    func relabel() {
        guard tabViewItems.count == 2 else { return }
        tabViewItems[0].label = L.s("General")
        tabViewItems[0].viewController?.title = L.s("General")
        tabViewItems[1].label = L.s("Models")
        tabViewItems[1].viewController?.title = L.s("Models")
        view.window?.title = selectedLabel
    }
}

/// Language, history, and the single sentence about updates. Everything else this pane used
/// to carry — the presence switches, three restatements of the privacy promise, a paragraph
/// of network disclosure — is gone: the switches with the surfaces they controlled, the
/// copy because a settings pane is not a compliance document.
struct GeneralPane: View {
    let model: AppModel
    @Bindable var preferences: Preferences
    let updates: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Picker(selection: $preferences.appearanceID) {
                        Text(L.s("System")).tag("system")
                        Text(L.s("Light")).tag("light")
                        Text(L.s("Dark")).tag("dark")
                    } label: {
                        Text(L.s("Appearance"))
                    }
                    .pickerStyle(.menu)

                    Picker(selection: $preferences.languageID) {
                        Text(L.s("System")).tag(L.systemID)
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "简体中文").tag("zh-Hans")
                    } label: {
                        Text(L.s("Language"))
                    }
                    .pickerStyle(.menu)
                }

                HistorySection(model: model, preferences: preferences)

                if updates.isAvailable {
                    Section {
                        Toggle(isOn: $preferences.checksForUpdates) {
                            Text(L.s("Check for updates automatically"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .onChange(of: preferences.checksForUpdates) { _, on in
                            updates.setAutomaticChecks(on)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            // The one claim the whole product rests on, made once, in the place a doubting
            // user looks first.
            Text(L.s("Your pictures never leave your Mac."))
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
/// The size on the Clear button is the whole reason this section is not just a switch:
/// "Clear recent cutouts" with no number beside it is a button nobody presses because
/// nobody knows whether it is worth pressing.
private struct HistorySection: View {
    let model: AppModel
    @Bindable var preferences: Preferences

    /// Nil until the walk finishes, and again the moment the grid changes — the number is
    /// re-measured rather than adjusted, because a running total is one more thing that can
    /// drift out of agreement with the disk.
    @State private var bytes: Int64?

    private var clearTitle: String {
        guard let size = bytes.flatMap(EngineLabels.megabytes(orNothing:)) else {
            return L.s("Clear History")
        }
        return String(format: L.s("Clear History (%@)"), size)
    }

    var body: some View {
        Section {
            Toggle(isOn: $preferences.keepsHistory) {
                Text(L.s("Keep recent cutouts between launches"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: preferences.keepsHistory) { _, keeps in
                guard !keeps else { return }
                model.forgetStoredHistory()
            }
            Button(clearTitle) { model.clearRecents() }
                .disabled(model.recents.items.isEmpty)
        } header: {
            Text(L.s("History"))
        }
        // Re-measured whenever the grid changes size, which covers both directions: a batch
        // landing and the Clear this very button just performed.
        .task(id: model.recents.items.count) {
            let archive = preferences.archive
            bytes = await Task.detached(priority: .utility) { archive.totalBytes() }.value
        }
    }
}

/// The default engine, and the models that can be one. Two different questions, asked
/// separately: one pop-up that states the preference in a sentence, listing only engines
/// that can actually serve it, and below it a plain management list.
private struct ModelsPane: View {
    let preferences: Preferences

    @State private var store = ModelStore()

    var body: some View {
        ModelsForm(store: store, preferences: preferences)
            .frame(width: 480, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ModelsForm: View {
    @Bindable var store: ModelStore
    @Bindable var preferences: Preferences

    /// Everything that could be the default right now: Vision, which is always here, plus
    /// whatever is on disk.
    private var choices: [String] {
        [EngineCatalog.defaultEngineID] + store.rows.filter(\.isInstalled).map(\.id)
    }

    /// Reads through the same fallback the pipeline uses rather than writing it back:
    /// `Preferences.engineID` deliberately keeps pointing at a model that has been deleted,
    /// so the pop-up shows what today's drop would actually use, and only a deliberate
    /// choice stores anything.
    private var selection: Binding<String> {
        Binding(
            get: { choices.contains(preferences.engineID) ? preferences.engineID : EngineCatalog.defaultEngineID },
            set: { preferences.engineID = $0 }
        )
    }

    var body: some View {
        Form {
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
            }

            Section {
                if store.registry == nil {
                    Text(L.s("This build carries no model list."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.rows) { row in
                    ModelRowView(row: row, store: store, preferences: preferences)
                }
            } header: {
                Text(L.s("Models"))
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .task { await store.measureInstalled() }
    }
}

/// The shape every model row has: a face, what it is for, what it is, and the one button
/// that changes its state.
private struct EngineRow<Control: View>: View {
    let id: String
    let title: String
    /// The model's technical identity, on one line: real name, licence, size. Small,
    /// tertiary — skippable by everyone it is not for.
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

/// A face for the row, in place of vendor logos: Apple's mark is a trademark this app has
/// no licence to wear, and BiRefNet has no mark at all. A tinted glyph of the *edge* each
/// engine cuts does the same job without borrowing anyone's identity. The wash follows the
/// system accent, like every other tinted element in the app now does.
private struct IconTile: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0.16)],
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
                Button(L.s("Cancel")) { store.cancel(row.id) }
            }
        case .installed where row.isOutdated:
            // The new bytes arrived with the app update; fetching them is still the
            // user's click, like every other download in this app.
            HStack(spacing: 8) {
                Button(L.s("Update")) { store.download(row.id, force: true) }
                Button(L.s("Delete")) { store.delete(row.id, preferences: preferences) }
            }
        case .installed:
            Button(L.s("Delete")) { store.delete(row.id, preferences: preferences) }
        case .available, .failed:
            Button(L.s("Download")) { store.download(row.id) }
        }
    }
}
