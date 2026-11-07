import AppKit
import SwiftUI

// MARK: - Packs

/// A pack, shown with an original badge (a theme symbol on a gradient) rather than EA's
/// artwork, so the app can be shared freely.
struct SimsPack: Identifiable {
    let code: String   // folder name under "The Sims 3 Packs", e.g. "EP05"
    let name: String
    let symbol: String
    let colors: (Color, Color)
    var id: String { code }
    var isExpansion: Bool { code.hasPrefix("EP") }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

enum SimsPacks {
    static let expansions: [SimsPack] = [
        SimsPack(code: "EP01", name: "World Adventures", symbol: "globe.europe.africa.fill",
                 colors: (rgb(1.00, 0.72, 0.30), rgb(0.85, 0.40, 0.10))),
        SimsPack(code: "EP02", name: "Ambitions", symbol: "briefcase.fill",
                 colors: (rgb(0.45, 0.78, 1.00), rgb(0.12, 0.45, 0.85))),
        SimsPack(code: "EP03", name: "Late Night", symbol: "moon.stars.fill",
                 colors: (rgb(0.95, 0.35, 0.70), rgb(0.45, 0.12, 0.55))),
        SimsPack(code: "EP04", name: "Generations", symbol: "figure.2.and.child.holdinghands",
                 colors: (rgb(0.95, 0.75, 0.40), rgb(0.60, 0.38, 0.15))),
        SimsPack(code: "EP05", name: "Pets", symbol: "pawprint.fill",
                 colors: (rgb(0.72, 0.68, 1.00), rgb(0.40, 0.35, 0.80))),
        SimsPack(code: "EP06", name: "Showtime", symbol: "music.mic",
                 colors: (rgb(0.35, 0.60, 1.00), rgb(0.10, 0.15, 0.60))),
        SimsPack(code: "EP07", name: "Supernatural", symbol: "wand.and.stars",
                 colors: (rgb(0.30, 0.75, 0.55), rgb(0.05, 0.28, 0.22))),
        SimsPack(code: "EP08", name: "Seasons", symbol: "leaf.fill",
                 colors: (rgb(0.55, 0.85, 0.40), rgb(0.90, 0.45, 0.20))),
        SimsPack(code: "EP09", name: "University Life", symbol: "graduationcap.fill",
                 colors: (rgb(1.00, 0.60, 0.25), rgb(0.80, 0.30, 0.05))),
        SimsPack(code: "EP10", name: "Island Paradise", symbol: "beach.umbrella.fill",
                 colors: (rgb(0.30, 0.85, 0.90), rgb(0.05, 0.45, 0.70))),
        SimsPack(code: "EP11", name: "Into the Future", symbol: "atom",
                 colors: (rgb(0.55, 0.90, 1.00), rgb(0.30, 0.25, 0.75))),
    ]

    static let stuff: [SimsPack] = [
        SimsPack(code: "SP01", name: "High-End Loft Stuff", symbol: "building.2.fill",
                 colors: (rgb(0.70, 0.90, 0.45), rgb(0.30, 0.55, 0.20))),
        SimsPack(code: "SP02", name: "Fast Lane Stuff", symbol: "car.side.fill",
                 colors: (rgb(0.40, 0.55, 1.00), rgb(0.08, 0.15, 0.50))),
        SimsPack(code: "SP03", name: "Outdoor Living Stuff", symbol: "tree.fill",
                 colors: (rgb(0.55, 0.85, 1.00), rgb(0.25, 0.65, 0.30))),
        SimsPack(code: "SP04", name: "Town Life Stuff", symbol: "storefront.fill",
                 colors: (rgb(0.85, 0.88, 0.95), rgb(0.45, 0.52, 0.65))),
        SimsPack(code: "SP05", name: "Master Suite Stuff", symbol: "bed.double.fill",
                 colors: (rgb(0.95, 0.40, 0.45), rgb(0.55, 0.08, 0.18))),
        SimsPack(code: "SP06", name: "Katy Perry's Sweet Treats", symbol: "birthday.cake.fill",
                 colors: (rgb(1.00, 0.60, 0.80), rgb(0.85, 0.25, 0.55))),
        SimsPack(code: "SP07", name: "Diesel Stuff", symbol: "tshirt.fill",
                 colors: (rgb(0.90, 0.85, 0.45), rgb(0.45, 0.42, 0.15))),
        SimsPack(code: "SP08", name: "70s, 80s & 90s Stuff", symbol: "music.note",
                 colors: (rgb(0.85, 0.45, 1.00), rgb(0.35, 0.10, 0.60))),
        SimsPack(code: "SP09", name: "Movie Stuff", symbol: "popcorn.fill",
                 colors: (rgb(0.95, 0.80, 0.45), rgb(0.25, 0.18, 0.10))),
    ]

    static var all: [SimsPack] { expansions + stuff }
}

extension Store {
    var packsFolder: URL? {
        gameURL?.deletingLastPathComponent()   // Resources
            .deletingLastPathComponent()       // Contents
            .deletingLastPathComponent()       // Sims3Launcher.app
            .deletingLastPathComponent()       // The Sims 3
            .appendingPathComponent("The Sims 3 Packs")
    }
}

// MARK: - Play screen

private let deepTop = Color(red: 0.03, green: 0.11, blue: 0.14)
private let deepBottom = Color(red: 0.01, green: 0.03, blue: 0.06)
private let simGreen = Color(red: 0.30, green: 0.85, blue: 0.38)

struct PlayView: View {
    @EnvironmentObject var store: Store
    /// Lays out without a scroll view and freezes the plumbob, so the screen can be
    /// rendered to an image for design checks.
    var snapshot = false
    @State private var installed: Set<String> = []

    private var installedPacks: Set<String> { snapshot ? Self.installedPacks(store) : installed }
    private var installedCount: Int { SimsPacks.all.filter { installedPacks.contains($0.code) }.count }

    var body: some View {
        ZStack {
            LinearGradient(colors: [deepTop, deepBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [simGreen.opacity(0.22), .clear],
                           center: UnitPoint(x: 0.5, y: 0.22), startRadius: 0, endRadius: 360)

            if snapshot {
                content
            } else {
                ScrollView { content }
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle("Home")
        .onAppear(perform: loadPacks)
        .onChange(of: store.gameURL) { _, _ in loadPacks() }
    }

    private var content: some View {
                VStack(spacing: 0) {
                    PlumbobLoop(paused: store.gameRunning || !store.appVisible, still: snapshot)
                        .frame(width: 92, height: 150)
                        .padding(.top, 28)

                    Text("The Sims 3")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 14)
                    if store.gameURL != nil {
                        Text("\(installedCount) of \(SimsPacks.all.count) packs installed")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 2)
                    }

                    playControls
                        .padding(.top, 22)

                    alerts
                        .padding(.top, 14)

                    ImportSection(snapshot: snapshot)
                        .padding(.top, 20)

                    if store.gameURL != nil {
                        packsPanel
                            .padding(.top, 18)
                            .padding(.bottom, 28)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
    }

    // MARK: pieces

    @ViewBuilder private var playControls: some View {
        if store.gameURL == nil {
            VStack(spacing: 10) {
                Text(store.gameMissingReason)
                    .foregroundStyle(.orange)
                Button("Locate Game…") { store.chooseGame() }
            }
        } else {
            VStack(spacing: 12) {
                Button {
                    store.play()
                } label: {
                    Label(store.gameRunning ? "Playing" : "Play",
                          systemImage: store.gameRunning ? "gamecontroller.fill" : "play.fill")
                }
                .buttonStyle(GlowButtonStyle(enabled: !store.gameRunning))
                .disabled(store.gameRunning)
                .keyboardShortcut(.defaultAction)

                HStack(spacing: 10) {
                    Menu {
                        Picker("Resolution", selection: $store.resolutionChoice) {
                            ForEach(ResolutionChoice.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        OptionChip(icon: "display", text: store.resolutionChoice.short)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Resolution the game starts in. 1080p window is the safe choice. Fullscreen at a resolution other than your screen's own (such as 1440p on a 4K screen) can make clicks land in the wrong place.")

                    Menu {
                        Picker("Play sound through", selection: outputBinding) {
                            Text("Current output (\(store.audioDevice?.name ?? "none"))").tag("")
                            ForEach(store.outputDevices, id: \.uid) { dev in
                                Text(dev.name).tag(dev.uid)
                            }
                            if store.playDeviceMissing {
                                Text("\(store.playOutputName) (not connected)").tag(store.playOutputUID)
                            }
                        }
                        .pickerStyle(.inline)
                        Picker("Sample rate", selection: $store.playSampleRate) {
                            Text("Don't change").tag(0.0)
                            ForEach(soundRates, id: \.self) { Text(AudioOutput.label($0)).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        OptionChip(icon: "speaker.wave.2.fill", text: soundLabel, warning: soundUnsupported)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(soundHelp)
                }

                HStack(spacing: 18) {
                    Toggle("Clear caches first", isOn: $store.clearCachesOnPlay)
                        .toggleStyle(GreenCheckboxStyle())
                        .help("Deletes the game's cache files before starting. Helps after adding or removing mods.")
                    TestingCheatsGuide()
                }
            }
        }
    }

    private var outputBinding: Binding<String> {
        Binding(get: { store.playOutputUID }, set: { uid in
            store.playOutputUID = uid
            if let dev = store.outputDevices.first(where: { $0.uid == uid }) { store.playOutputName = dev.name }
        })
    }

    private var soundRates: [Double] {
        var rates = store.playDevice?.supportedRates.filter { $0 >= 32000 } ?? [44100, 48000, 96000]
        if store.playSampleRate > 0, !rates.contains(store.playSampleRate) { rates.append(store.playSampleRate) }
        return rates.sorted()
    }

    private var soundUnsupported: Bool {
        if store.playDeviceMissing { return true }
        guard store.playSampleRate > 0, let dev = store.playDevice else { return false }
        return !dev.supportedRates.contains(store.playSampleRate)
    }

    private var soundLabel: String {
        let rate = store.playSampleRate > 0 ? AudioOutput.label(store.playSampleRate) : "rate as is"
        if store.playOutputUID.isEmpty { return store.playSampleRate > 0 ? rate : "Sound as is" }
        return "\(store.playOutputName) · \(rate)"
    }

    private var soundHelp: String {
        if store.playDeviceMissing {
            return "\(store.playOutputName) isn't connected. Until it is, Play leaves the sound as it is."
        }
        guard let dev = store.playDevice else { return "Sound output while the game runs." }
        var parts: [String] = []
        if !store.playOutputUID.isEmpty, dev.uid != store.audioDevice?.uid {
            parts.append("While the game runs, sound plays through \(dev.name)")
        } else {
            parts.append("Sound plays through \(dev.name)")
        }
        if store.playSampleRate == 0 {
            parts.append("at its current \(AudioOutput.label(dev.rate)).")
        } else if soundUnsupported {
            parts.append("but it can't run at \(AudioOutput.label(store.playSampleRate)), so the rate is left alone.")
        } else {
            parts.append("at \(AudioOutput.label(store.playSampleRate)).")
        }
        return parts.joined(separator: " ") + " Everything goes back when the game quits."
    }

    @ViewBuilder private var alerts: some View {
        VStack(spacing: 8) {
            if store.launchMode == .launcher {
                AlertChip(text: "The EA Launcher window is back", action: "Fix") {
                    store.setLaunchMode(.direct)
                }
            }
            if store.problemCount > 0 {
                AlertChip(text: "\(store.problemCount) mod\(store.problemCount == 1 ? "" : "s") won't load",
                          action: "Show") { store.pane = .mods }
            }
        }
    }

    private var packsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            PackRow(title: "Expansion Packs", packs: SimsPacks.expansions, installed: installedPacks)
            Divider().overlay(.white.opacity(0.08))
            PackRow(title: "Stuff Packs", packs: SimsPacks.stuff, installed: installedPacks)
        }
        .padding(20)
        .frame(maxWidth: 700)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func loadPacks() {
        installed = Self.installedPacks(store)
    }

    static func installedPacks(_ store: Store) -> Set<String> {
        guard let folder = store.packsFolder else { return [] }
        return Set(SimsPacks.all.filter {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.code).path)
        }.map(\.code))
    }
}

// MARK: - Pack grid

struct PackRow: View {
    let title: String
    let packs: [SimsPack]
    let installed: Set<String>
    @State private var hovered: SimsPack?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(packs.filter { installed.contains($0.code) }.count) of \(packs.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                if let h = hovered {
                    Text(h.name + (installed.contains(h.code) ? "" : " · not installed"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(installed.contains(h.code) ? .white : .white.opacity(0.5))
                        .transition(.opacity)
                }
            }
            .frame(height: 18)
            .animation(.easeOut(duration: 0.12), value: hovered?.code)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50, maximum: 58), spacing: 8)], spacing: 10) {
                ForEach(packs) { pack in
                    PackIcon(pack: pack, installed: installed.contains(pack.code))
                        .onHover { inside in
                            if inside { hovered = pack } else if hovered?.code == pack.code { hovered = nil }
                        }
                }
            }
        }
    }
}

/// Original pack badge: a glossy gradient tile with the pack's theme symbol. Expansions are
/// round, stuff packs are rounded squares.
struct PackBadge: View {
    let pack: SimsPack
    var size: CGFloat = 48

    var body: some View {
        let shape = pack.isExpansion
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        ZStack {
            shape.fill(LinearGradient(colors: [pack.colors.0, pack.colors.1],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            // soft top highlight
            shape.fill(LinearGradient(colors: [.white.opacity(0.35), .clear],
                                      startPoint: .top, endPoint: .center))
            Image(systemName: pack.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            shape.stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: pack.colors.1.opacity(0.45), radius: 4, y: 2)
    }
}

struct PackIcon: View {
    let pack: SimsPack
    let installed: Bool
    @State private var hover = false

    var body: some View {
        PackBadge(pack: pack)
        .grayscale(installed ? 0 : 1)
        .opacity(installed ? 1 : 0.38)
        .shadow(color: installed && hover ? simGreen.opacity(0.6) : .clear, radius: 8)
        .scaleEffect(hover && installed ? 1.1 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hover)
        .onHover { hover = $0 }
        .help(pack.name + (installed ? "" : " (not installed)"))
        .accessibilityLabel(pack.name + (installed ? ", installed" : ", not installed"))
    }
}

// MARK: - Chips and buttons

struct GlowButtonStyle: ButtonStyle {
    var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 230, height: 56)
            .background(
                Capsule().fill(LinearGradient(
                    colors: enabled
                        ? [Color(red: 0.40, green: 0.90, blue: 0.40), Color(red: 0.08, green: 0.56, blue: 0.22)]
                        : [Color.white.opacity(0.18), Color.white.opacity(0.10)],
                    startPoint: .top, endPoint: .bottom))
            )
            .overlay(Capsule().strokeBorder(.white.opacity(enabled ? 0.35 : 0.12), lineWidth: 1))
            .shadow(color: enabled ? simGreen.opacity(configuration.isPressed ? 0.25 : 0.55) : .clear,
                    radius: configuration.isPressed ? 8 : 18, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct OptionChip: View {
    let icon: String
    let text: String
    var warning = false
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : icon)
                .foregroundStyle(warning ? Color.orange : simGreen.opacity(0.9))
            Text(text)
                .foregroundStyle(.white.opacity(0.85))
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(hover ? 0.12 : 0.07)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .contentShape(Capsule())
        .onHover { hover = $0 }
    }
}

struct GreenCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isOn ? simGreen : Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(.white.opacity(configuration.isOn ? 0 : 0.3), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .opacity(configuration.isOn ? 1 : 0)
                    )
                    .frame(width: 16, height: 16)
                configuration.label
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: configuration.isOn)
    }
}

// MARK: - Import section

struct ImportSection: View {
    @EnvironmentObject var store: Store
    var snapshot = false
    @State private var targeted = false

    private var expanded: Bool { store.importExpanded || snapshot }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { store.importExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.fill").foregroundStyle(simGreen)
                    Text("Import mods").fontWeight(.semibold)
                    if store.importing { ProgressView().controlSize(.small) }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Capsule().fill(.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            if expanded {
                panel
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: store.importing ? "hourglass" : "tray.and.arrow.down")
                    .font(.system(size: 28))
                    .foregroundStyle(targeted ? simGreen : .white.opacity(0.5))
                Text(store.importing ? "Importing…" : "Drop .package, .sims3pack or .zip files here")
                    .foregroundStyle(.white.opacity(0.85))
                Button("Choose Files…") { store.chooseFilesToImport() }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(targeted ? simGreen : .white.opacity(0.25))
            )
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                loadURLs(providers) { store.importItems($0) }
                return true
            }

            HStack(spacing: 12) {
                Toggle("Import Sims 3 mods I download automatically", isOn: $store.autoImportDownloads)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .foregroundStyle(.white.opacity(0.8))
                    .help("Watches your Downloads folder and imports new Sims 3 mods as soon as they finish downloading. Sims 4 mods are ignored.")
                Spacer()
                Text("Get mods:").foregroundStyle(.white.opacity(0.5))
                Link("Nexus Mods", destination: URL(string: "https://www.nexusmods.com/games/thesims3/mods")!)
                Link("Mod The Sims", destination: URL(string: "https://modthesims.info/browse.php?gs=3")!)
            }
            .font(.callout)

            if !store.results.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionLabel("Recently imported")
                        Spacer()
                        Button("Clear") { store.results.removeAll() }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(store.results.prefix(5)) { r in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(r.ok ? simGreen : .red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.source).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                                Text(r.message).font(.caption).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        .font(.callout)
                    }
                }
            }

            Divider().overlay(.white.opacity(0.08))
            RecommendedModsView()
        }
        .padding(18)
        .frame(maxWidth: 700)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.5))
    }
}

// MARK: - Recommended mods

/// Mods worth having, listed with links rather than bundled: bundling would mean
/// redistributing other people's work, and copies would go stale as authors update them.
struct RecommendedMod: Identifiable {
    let id: String          // file name prefix used to spot it in Mods
    let name: String
    let why: String
    let url: String

    static let all: [RecommendedMod] = [
        RecommendedMod(id: "nraas_overwatch", name: "NRaas Overwatch",
                       why: "Keeps saves running smoothly, and can switch on testing cheats every time you load.",
                       url: "https://www.nraas.net/community/Overwatch"),
        RecommendedMod(id: "nraas_errortrap", name: "NRaas ErrorTrap",
                       why: "Catches script errors and repairs broken objects before they cause trouble.",
                       url: "https://www.nraas.net/community/ErrorTrap"),
        RecommendedMod(id: "nraas_mastercontroller", name: "NRaas Master Controller",
                       why: "Edit Sims, households and the whole town from one menu.",
                       url: "https://www.nraas.net/community/MasterController"),
    ]
}

extension Store {
    func hasMod(_ prefix: String) -> Bool {
        mods.contains { $0.area != .library && $0.status != .disabled && $0.name.lowercased().hasPrefix(prefix) }
    }
}

struct RecommendedModsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Recommended mods")
            ForEach(RecommendedMod.all) { mod in
                let installed = store.hasMod(mod.id)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: installed ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(installed ? simGreen : .white.opacity(0.4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mod.name).foregroundStyle(.white)
                        Text(mod.why).font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    if installed {
                        Text("Installed").font(.caption).foregroundStyle(.white.opacity(0.5))
                    } else {
                        Link("Get", destination: URL(string: mod.url)!).font(.callout.weight(.semibold))
                    }
                }
                .font(.callout)
            }
            Text("Download a mod from its page and it's imported automatically (or drop it above).")
                .font(.caption).foregroundStyle(.white.opacity(0.4))
        }
    }
}

// MARK: - Testing cheats

struct TestingCheatsGuide: View {
    @EnvironmentObject var store: Store
    @State private var show = false

    private var overwatch: Bool { store.hasMod("nraas_overwatch") }

    var body: some View {
        Button { show.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: overwatch ? "wand.and.stars" : "exclamationmark.triangle.fill")
                    .foregroundStyle(overwatch ? simGreen : .orange)
                Text("Testing cheats on load")
                    .foregroundStyle(.white.opacity(0.7))
                Image(systemName: "info.circle")
                    .foregroundStyle(.white.opacity(0.45))
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Testing cheats every time you load").font(.headline)
                if overwatch {
                    Text("NRaas Overwatch is installed. Switch this on once in each save:")
                    Text("1. In the game, click the Town Hall's map tag (or any computer) → NRaas → More → Overwatch.\n2. Choose Settings → Testing Cheats Enabled and set it to True.\n3. Save the game.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("From then on Overwatch turns testing cheats on whenever that save loads.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("This uses the NRaas Overwatch mod, which isn't installed. Get it from Recommended mods under Import mods, then switch on Overwatch → Settings → Testing Cheats Enabled in each save.")
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Get NRaas Overwatch", destination: URL(string: "https://www.nraas.net/community/Overwatch")!)
                }
            }
            .font(.callout)
            .padding(16)
            .frame(width: 360)
        }
    }
}

struct AlertChip: View {
    let text: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .foregroundStyle(.white.opacity(0.85))
            Button(action, action: perform)
                .buttonStyle(.plain)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.orange.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Plumbob

/// The plumbob's frames are drawn once, then played back like a GIF: showing a ready-made
/// image costs almost nothing, whereas drawing the shape and its glow live used ~14% CPU.
/// (A real GIF can't hold the soft, semi-transparent glow, so the frames stay in memory.)
@MainActor
final class PlumbobFrames {
    static let shared = PlumbobFrames()
    static let size = CGSize(width: 92, height: 150)
    static let fps = 24.0
    /// The six-sided shape looks identical every sixth of a turn, so one sixth loops.
    static let turnSeconds = 2.0
    static let bobSeconds = 4.0
    static let glowPadding: CGFloat = 80

    let frames: [CGImage]
    let glow: CGImage?

    private init() {
        let count = Int(Self.fps * Self.turnSeconds)
        frames = (0..<count).compactMap { i in
            let angle = Double(i) / Double(count) * (.pi / 3)
            let r = ImageRenderer(content: Canvas { gc, size in
                Plumbob.draw(in: &gc, size: size, angle: angle)
            }.frame(width: Self.size.width, height: Self.size.height))
            r.scale = 2
            return r.cgImage
        }
        let pad = Self.glowPadding
        let silhouette = Canvas { gc, size in
            let w = size.width, h = size.height
            var p = Path()
            p.move(to: CGPoint(x: w / 2, y: h * 0.02))
            p.addLine(to: CGPoint(x: w * 0.95, y: h * 0.40))
            p.addLine(to: CGPoint(x: w / 2, y: h * 0.98))
            p.addLine(to: CGPoint(x: w * 0.05, y: h * 0.40))
            p.closeSubpath()
            gc.fill(p, with: .color(simGreen))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        let g = ImageRenderer(content: ZStack {
            silhouette.blur(radius: 40).opacity(0.45)
            silhouette.blur(radius: 16).opacity(0.75)
        }
        .frame(width: Self.size.width + pad * 2, height: Self.size.height + pad * 2))
        g.scale = 2
        glow = g.cgImage
    }
}

/// A slowly turning, gently floating plumbob.
struct PlumbobLoop: View {
    var paused = false
    /// Shows one frame without animating (for rendering the screen to an image).
    var still = false

    var body: some View {
        Group {
            if still {
                frame(at: 0.5)
            } else {
                TimelineView(.animation(minimumInterval: 1 / PlumbobFrames.fps, paused: paused)) { context in
                    frame(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func frame(at t: Double) -> some View {
        let f = PlumbobFrames.shared
        let n = f.frames.count
        let phase = t.truncatingRemainder(dividingBy: PlumbobFrames.turnSeconds) / PlumbobFrames.turnSeconds
        let index = n > 0 ? min(n - 1, Int(phase * Double(n))) : 0
        let bob = CGFloat(sin(t * 2 * .pi / PlumbobFrames.bobSeconds)) * 5
        return ZStack {
            if let glow = f.glow {
                Image(decorative: glow, scale: 2)
            }
            if n > 0 {
                Image(decorative: f.frames[index], scale: 2)
            }
        }
        .frame(width: PlumbobFrames.size.width, height: PlumbobFrames.size.height)
        .offset(y: bob)
    }
}

/// Draws the plumbob as a shaded six-sided bipyramid.
enum Plumbob {
    static func draw(in gc: inout GraphicsContext, size: CGSize, angle: Double) {
        let sides = 6
        let w = Double(size.width), h = Double(size.height)
        let cx = w / 2
        let r = w * 0.47
        let yTop = h * 0.02, yMid = h * 0.40, yBottom = h * 0.98
        let topH = yMid - yTop, bottomH = yBottom - yMid
        let apothem = r * cos(.pi / Double(sides))
        // light from upper left, toward the viewer
        let light = normalize((-0.45, 0.75, 0.6))

        func equator(_ k: Int) -> (x: Double, z: Double) {
            let th = angle + Double(k) * 2 * .pi / Double(sides)
            return (cx + r * sin(th), r * cos(th))
        }

        for half in [false, true] {   // false = upper pyramid, true = lower
            for k in 0..<sides {
                let mid = angle + (Double(k) + 0.5) * 2 * .pi / Double(sides)
                guard cos(mid) > 0 else { continue }   // facing away
                let height = half ? bottomH : topH
                let n = normalize((sin(mid) * height, (half ? -1 : 1) * apothem, cos(mid) * height))
                let lambert = max(0, n.0 * light.0 + n.1 * light.1 + n.2 * light.2)
                let shade = 0.18 + 0.82 * lambert

                let a = equator(k), b = equator(k + 1)
                let apex = CGPoint(x: cx, y: half ? yBottom : yTop)
                var p = Path()
                p.move(to: apex)
                p.addLine(to: CGPoint(x: a.x, y: yMid))
                p.addLine(to: CGPoint(x: b.x, y: yMid))
                p.closeSubpath()

                let base = mix(shade)
                let tip = mix(min(1, shade + (half ? 0.0 : 0.18)))
                gc.fill(p, with: .linearGradient(
                    Gradient(colors: [tip, base]),
                    startPoint: apex,
                    endPoint: CGPoint(x: (a.x + b.x) / 2, y: yMid)))
                gc.stroke(p, with: .color(.white.opacity(0.18)), lineWidth: 0.7)
            }
        }
    }

    private static func mix(_ s: Double) -> Color {
        // dark emerald → bright lime
        let dark = (0.01, 0.30, 0.10), light = (0.62, 1.0, 0.48)
        return Color(red: dark.0 + (light.0 - dark.0) * s,
                     green: dark.1 + (light.1 - dark.1) * s,
                     blue: dark.2 + (light.2 - dark.2) * s)
    }

    private static func normalize(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
        let l = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
        return l == 0 ? v : (v.0 / l, v.1 / l, v.2 / l)
    }
}
