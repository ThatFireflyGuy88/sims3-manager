import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Pane: String, CaseIterable, Identifiable {
    case play = "Home"
    case mods = "Mods"
    case streamDeck = "Stream Deck"
    case tools = "Tools"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .play: return "house"
        case .mods: return "puzzlepiece.extension"
        case .streamDeck: return "square.grid.3x2"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

// MARK: - Window

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var menuOpen = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    Group {
                        switch store.pane {
                        case .play: PlayView()
                        case .mods: ModsView()
                        case .streamDeck: StreamDeckView()
                        case .tools: ToolsView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let notice = store.notice {
                        NoticeBar(text: notice) { store.notice = nil }
                    }
                }

                if menuOpen {
                    Color.black.opacity(0.3)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleMenu() }
                        .transition(.opacity)
                    SideMenu { pane in
                        store.pane = pane
                        toggleMenu()
                    }
                    .transition(.move(edge: .trailing))
                }
            }
            .toolbar {
                if !store.screenshotMode {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: toggleMenu) {
                        Image(systemName: menuOpen ? "xmark" : "line.3.horizontal")
                            .frame(width: 18)
                    }
                    .help("Menu")
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadURLs(providers) { store.importItems($0); store.showImport() }
            return true
        }
    }

    private func toggleMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { menuOpen.toggle() }
    }
}

struct SideMenu: View {
    @EnvironmentObject var store: Store
    let choose: (Pane) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sims 3 Manager")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            ForEach(Pane.allCases) { pane in
                Button { choose(pane) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: pane.icon).frame(width: 22)
                        Text(pane.rawValue)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(store.pane == pane ? Color.accentColor.opacity(0.18) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.body.weight(store.pane == pane ? .semibold : .regular))
            }
            Spacer()
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .overlay(alignment: .leading) { Divider() }
        .shadow(color: .black.opacity(0.25), radius: 16, x: -4)
    }
}

func loadURLs(_ providers: [NSItemProvider], then: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for p in providers {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { then(urls) }
}

struct NoticeBar: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "info.circle")
            Text(text).textSelection(.enabled)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(10)
        .background(.bar)
    }
}

// MARK: - Mods

enum ModFilter: String, CaseIterable, Identifiable {
    case all = "All", active = "Active", disabled = "Disabled", library = "Library", problems = "Problems"
    var id: String { rawValue }

    func matches(_ m: ModItem) -> Bool {
        switch self {
        case .all: return true
        case .active: return m.status == .active || m.status == .override
        case .disabled: return m.status == .disabled
        case .library: return m.area == .library
        case .problems: return m.status == .tooDeep || m.status == .needsConversion
        }
    }
}

struct ModsView: View {
    @EnvironmentObject var store: Store
    @State private var selection = Set<ModItem.ID>()
    @State private var query = ""
    @State private var filter: ModFilter = .all
    @State private var confirmTrash: [ModItem] = []
    @State private var sortOrder = [KeyPathComparator(\ModItem.displayName)]

    private var rows: [ModItem] {
        store.mods.filter { m in
            filter.matches(m) && (query.isEmpty
                || m.displayName.localizedCaseInsensitiveContains(query)
                || m.name.localizedCaseInsensitiveContains(query)
                || m.kind.rawValue.localizedCaseInsensitiveContains(query)
                || m.folder.localizedCaseInsensitiveContains(query))
        }
        .sorted(using: sortOrder)
    }

    private func items(_ ids: Set<ModItem.ID>) -> [ModItem] {
        store.mods.filter { ids.contains($0.id) }
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.displayName) { m in
                HStack(spacing: 8) {
                    Image(systemName: m.status.icon).foregroundStyle(m.status.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.displayName).lineLimit(1)
                        if m.displayName != m.name {
                            Text(m.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .help(m.url.path)
            }
            .width(min: 180, ideal: 280)
            TableColumn("Type", value: \.kind.rawValue) { m in
                Label(m.kind.rawValue, systemImage: m.kind.icon)
                    .foregroundStyle(m.kind == .unknown ? .tertiary : .primary)
            }
            .width(min: 90, ideal: 120, max: 160)
            TableColumn("Status", value: \.status.label) { m in
                Text(m.status.label).foregroundStyle(m.status.color)
            }
            .width(min: 80, ideal: 120, max: 200)
            TableColumn("Location", value: \.folder) { m in
                Text(m.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 80, ideal: 160)
            TableColumn("Size", value: \.size) { m in
                Text(formatBytes(m.size)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 55, ideal: 70, max: 90)
        }
        .contextMenu(forSelectionType: ModItem.ID.self) { ids in
            let sel = items(ids)
            if sel.contains(where: { $0.status == .disabled }) {
                Button("Enable") { store.setEnabled(sel, true) }
            }
            if sel.contains(where: canDisable) {
                Button("Disable") { store.setEnabled(sel, false) }
            }
            if sel.contains(where: { $0.status == .needsConversion }) {
                Button("Convert to .package") { store.convertInPlace(sel) }
            }
            Divider()
            Button("Show in Finder") { store.reveal(sel.map(\.url)) }
            Button("Move to Trash…") { confirmTrash = sel }
        } primaryAction: { ids in
            store.reveal(items(ids).map(\.url))
        }
        .searchableUnless(store.screenshotMode, text: $query, prompt: "Search mods")
        .toolbar {
            if !store.screenshotMode {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $filter) {
                    ForEach(ModFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItemGroup {
                let sel = items(selection)
                Button { store.setEnabled(sel, true) } label: { Label("Enable", systemImage: "checkmark.circle") }
                    .disabled(!sel.contains { $0.status == .disabled })
                Button { store.setEnabled(sel, false) } label: { Label("Disable", systemImage: "pause.circle") }
                    .disabled(!sel.contains(where: canDisable))
                Button { confirmTrash = sel } label: { Label("Trash", systemImage: "trash") }
                    .disabled(sel.isEmpty)
                Button { store.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            }
        }
        .navigationTitle("Mods")
        .navigationSubtitle("\(store.activeCount) active · \(store.disabledCount) disabled · \(store.library.count) in Library")
        .confirmationDialog("Move \(confirmTrash.count) item\(confirmTrash.count == 1 ? "" : "s") to the Trash?",
                            isPresented: Binding(get: { !confirmTrash.isEmpty }, set: { if !$0 { confirmTrash = [] } })) {
            Button("Move to Trash", role: .destructive) {
                store.moveToTrash(confirmTrash.map(\.url))
                selection.removeAll()
                confirmTrash = []
            }
        } message: {
            Text("You can get them back from the Trash until it's emptied.")
        }
    }

    private func canDisable(_ m: ModItem) -> Bool {
        m.status != .disabled && m.status != .needsConversion && m.area != .library
    }
}

// MARK: - Tools

struct ToolsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            Section("Caches") {
                LabeledContent("Game caches") {
                    Text(formatBytes(store.cacheSize)).monospacedDigit()
                }
                Text("Clearing caches fixes many glitches after adding or removing mods. The game rebuilds them on next launch. Files go to the Trash.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Clear Caches") { store.clearCaches() }
                    .disabled(store.gameRunning)
            }
            Section("Mods folder") {
                LabeledContent("Resource.cfg") {
                    Text(store.hasModsFramework ? "Installed" : "Missing")
                        .foregroundStyle(store.hasModsFramework ? .green : .orange)
                }
                if !store.hasModsFramework {
                    Button("Set Up Mods Folder") { store.createModsFramework() }
                }
                Text("Disabled mods are kept in Mods/Disabled, which the game doesn't load.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Folders") {
                Button("Open Sims 3 Folder") { NSWorkspace.shared.open(store.paths.user) }
                Button("Open Mods Folder") { NSWorkspace.shared.open(store.paths.mods) }
                Button("Open Library Folder") { NSWorkspace.shared.open(store.paths.library) }
            }
            Section("Game") {
                LabeledContent("Location") {
                    Text(store.gameURL?.path ?? "Not found")
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Button("Locate Game…") { store.chooseGame() }
            }
            Section("EA Launcher window") {
                LabeledContent("When you press Play") {
                    switch store.launchMode {
                    case .direct: Text("Goes straight into the game").foregroundStyle(.green)
                    case .launcher: Text("Opens the EA Launcher first").foregroundStyle(.orange)
                    case .unknown: Text("Unrecognised setting").foregroundStyle(.orange)
                    case .missing: Text("Setting not found").foregroundStyle(.secondary)
                    }
                }
                Text("The EA app still checks your license either way. An EA app Repair or update can switch this back; if that happens, use the button below.")
                    .font(.callout).foregroundStyle(.secondary)
                switch store.launchMode {
                case .launcher:
                    Button("Skip the Launcher Window") { store.setLaunchMode(.direct) }
                case .direct:
                    Button("Restore EA's Original Setting") { store.setLaunchMode(.launcher) }
                default:
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tools")
    }
}

extension View {
    /// Search field, left out while drawing README screenshots (it doesn't render offscreen).
    @ViewBuilder
    func searchableUnless(_ hide: Bool, text: Binding<String>, prompt: String) -> some View {
        if hide { self } else { searchable(text: text, prompt: Text(prompt)) }
    }
}
