import AppKit
import SwiftUI

struct StreamDeckView: View {
    @EnvironmentObject var store: Store
    @State private var creating = false

    private var slotCount: Int { store.deckDevice.columns * store.deckDevice.rows }
    private var layout: [SDAction] {
        Array((store.deckLayout + Array(repeating: SDAction.none, count: slotCount)).prefix(slotCount))
    }

    var body: some View {
        Form {
            Section {
                Picker("Stream Deck model", selection: $store.deckDevice) {
                    ForEach(SDDevice.all) { Text($0.name).tag($0) }
                }
                if let detected = SDDevice.detected() {
                    Text("Found a \(detected.name) set up on this Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Buttons") {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        ForEach(0..<store.deckDevice.rows, id: \.self) { row in
                            GridRow {
                                ForEach(0..<store.deckDevice.columns, id: \.self) { col in
                                    KeySlot(action: binding(row * store.deckDevice.columns + col))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    HStack {
                        Text("Click a key to choose what it does. ⇄ marks two-state buttons, which alternate on each press.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") { store.deckLayout = SDDevice.defaultLayout }
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Cheat buttons") {
                Picker("Cheat console shortcut", selection: $store.consoleUsesControl) {
                    Text("⌘ Command + Shift + C").tag(false)
                    Text("⌃ Control + Shift + C").tag(true)
                }
                .help("The 64-bit Mac game normally uses Command. Switch to Control if the console doesn't open.")
                Text("Every button runs on the Stream Deck itself, so Sims 3 Manager doesn't need to be open while you play. Cheat buttons open the game's cheat console with this shortcut, paste the cheat and press Enter. Move Objects alternates on and off; if it gets out of step (for example after you type the cheat yourself), press it once more.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button {
                        addToStreamDeck()
                    } label: {
                        Label("Add to Stream Deck", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(creating)
                    Button("Save Profile…") { saveProfile() }
                    Spacer()
                }
                Text("Creates a \"The Sims 3\" profile, with its button icons, and opens it in the Stream Deck app, which asks to import it. The profile is linked to the game, so Stream Deck switches to it automatically whenever The Sims 3 is in front.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Stream Deck")
        .onAppear { store.updateVisibility() }
    }

    private func binding(_ i: Int) -> Binding<SDAction> {
        Binding(get: { layout[i] }, set: { new in
            var l = layout
            l[i] = new
            store.deckLayout = l
        })
    }

    private func profileURL() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sims3Manager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("The Sims 3.streamDeckProfile")
    }

    private func addToStreamDeck() {
        creating = true
        defer { creating = false }
        let url = profileURL()
        do {
            try StreamDeckProfile.write(device: store.deckDevice, layout: layout, gameApp: store.gameURL,
                                        consoleUsesControl: store.consoleUsesControl, to: url)
            NSWorkspace.shared.open(url)
            store.notice = "Opened the profile in Stream Deck. Confirm the import there."
        } catch {
            store.notice = "Couldn't create the profile: \(error.localizedDescription)"
        }
    }

    private func saveProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "The Sims 3.streamDeckProfile"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try StreamDeckProfile.write(device: store.deckDevice, layout: layout, gameApp: store.gameURL,
                                        consoleUsesControl: store.consoleUsesControl, to: url)
            store.notice = "Saved \(url.lastPathComponent). Double-click it to import it into Stream Deck."
        } catch {
            store.notice = "Couldn't save the profile: \(error.localizedDescription)"
        }
    }
}

struct KeySlot: View {
    @Binding var action: SDAction

    private static let groups: [(String, [SDAction])] = [
        ("Time", [.pausePlay, .speedCycle, .pause, .speed1, .speed2, .speed3]),
        ("View", [.wallsNext, .wallsPrevious, .floorUp, .floorDown, .nextSim, .centerSim]),
        ("Modes", [.liveMode, .buyMode, .buildMode, .hideUI, .snapshot]),
        ("Cheats", [.moveObjects, .testingCheats]),
    ]

    var body: some View {
        Menu {
            ForEach(Self.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { a in
                        Button {
                            action = a
                        } label: {
                            Label(a.title + (a.isSwitch ? "  ⇄" : ""), systemImage: a.symbol)
                        }
                    }
                }
            }
            Divider()
            Button("Empty") { action = .none }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: action.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(action == .none ? Color.secondary : Color(red: 0.42, green: 0.92, blue: 0.45))
                Text(action == .none ? "Empty" : action.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(action == .none ? .secondary : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 84, height: 84)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(action == .none ? Color.secondary.opacity(0.08) : Color(red: 0.04, green: 0.12, blue: 0.11))
            )
            .overlay(alignment: .topTrailing) {
                if action.isSwitch {
                    Text("⇄").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(action.detail)
    }
}
