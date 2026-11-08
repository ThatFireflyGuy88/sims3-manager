import AppKit
import SwiftUI

enum ModArea: String {
    case packages = "Packages"
    case overrides = "Overrides"
    case library = "Library"
}

enum ModStatus {
    case active, override, disabled, tooDeep, needsConversion, inLibrary

    var label: String {
        switch self {
        case .active: return "Active"
        case .override: return "Active (override)"
        case .disabled: return "Disabled"
        case .tooDeep: return "Not loaded: folder too deep"
        case .needsConversion: return "Not loaded: .sims3pack"
        case .inLibrary: return "In Library"
        }
    }

    var icon: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .override: return "arrow.up.circle.fill"
        case .disabled: return "pause.circle"
        case .tooDeep, .needsConversion: return "exclamationmark.triangle.fill"
        case .inLibrary: return "house.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .active: return .green
        case .override: return .blue
        case .disabled: return .secondary
        case .tooDeep, .needsConversion: return .orange
        case .inLibrary: return .teal
        }
    }
}

struct ModItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let area: ModArea      // where it loads from (or would, when disabled)
    let relPath: String    // path relative to that area's folder
    let size: Int64
    let modified: Date
    let status: ModStatus
    var kind: ModKind = .unknown
    var friendlyName: String?

    var name: String { url.lastPathComponent }
    var displayName: String { friendlyName ?? PackageInfo.prettify(url) }
    var folder: String {
        let dir = (relPath as NSString).deletingLastPathComponent
        return dir.isEmpty ? area.rawValue : area.rawValue + "/" + dir
    }

    static func == (a: ModItem, b: ModItem) -> Bool {
        a.url == b.url && a.status == b.status && a.kind == b.kind && a.friendlyName == b.friendlyName
    }
    func hash(into h: inout Hasher) { h.combine(url) }
}

struct LibraryItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let modified: Date
    var name: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor
final class Store: ObservableObject {
    static let gameBundleID = "com.ea.mac.thesims3.game"
    static let cacheFiles = [
        "CASPartCache.package", "compositorCache.package", "scriptCache.package",
        "simCompositorCache.package", "socialCache.package",
    ]
    /// Resource.cfg loads Packages/*/*/*/*/*.package: up to four folders deep.
    static let maxDepth = 4

    let paths: Paths

    @Published var pane: Pane = .play
    @Published var importExpanded = false
    /// Set while drawing README screenshots: no Downloads watching, no toolbar buttons.
    @Published var screenshotMode = false
    /// False while the app is in the background or its window is hidden, so animations stop.
    @Published var appVisible = true

    // Stream Deck
    @Published var deckDevice: SDDevice {
        didSet { UserDefaults.standard.set(deckDevice.id, forKey: "deckDevice") }
    }
    @Published var deckLayout: [SDAction] {
        didSet { UserDefaults.standard.set(deckLayout.map(\.rawValue), forKey: "deckLayout") }
    }
    /// The 64-bit Mac game opens its cheat console with Cmd+Shift+C; some setups use Ctrl.
    @Published var consoleUsesControl: Bool {
        didSet { UserDefaults.standard.set(consoleUsesControl, forKey: "consoleUsesControl") }
    }

    @Published var mods: [ModItem] = []
    @Published var library: [LibraryItem] = []
    @Published var results: [ImportResult] = []
    @Published var importing = false
    @Published var gameURL: URL?
    @Published var gameRunning = false
    @Published var launchMode: LaunchConfig.Mode = .missing
    @Published var notice: String?
    @Published var clearCachesOnPlay: Bool {
        didSet { UserDefaults.standard.set(clearCachesOnPlay, forKey: "clearCachesOnPlay") }
    }

    @Published var resolutionChoice: ResolutionChoice {
        didSet { UserDefaults.standard.set(resolutionChoice.rawValue, forKey: "resolution") }
    }
    /// Output sample rate to use while the game runs; 0 leaves the device alone.
    @Published var playSampleRate: Double {
        didSet { UserDefaults.standard.set(playSampleRate, forKey: "playSampleRate") }
    }
    @Published var autoImportDownloads: Bool {
        didSet {
            UserDefaults.standard.set(autoImportDownloads, forKey: "autoImportDownloads")
            // Only pick up files that arrive after it's switched on.
            if autoImportDownloads { UserDefaults.standard.set(Date(), forKey: "watchDownloadsSince") }
        }
    }
    /// Output device to play through while the game runs; "" keeps whatever is current.
    @Published var playOutputUID: String {
        didSet { UserDefaults.standard.set(playOutputUID, forKey: "playOutputUID") }
    }
    /// Remembered so the menu can name the device while it's unplugged.
    @Published var playOutputName: String {
        didSet { UserDefaults.standard.set(playOutputName, forKey: "playOutputName") }
    }
    @Published var audioDevice: AudioOutput.Device?
    @Published var outputDevices: [AudioOutput.Device] = []

    /// Automatic display: the game runs in a 1080p window, which works on any Mac.
    @Published var displayAutomatic: Bool {
        didSet { UserDefaults.standard.set(displayAutomatic, forKey: "displayAutomatic") }
    }
    /// Automatic sound: the current output at 96 kHz, or the closest rate it supports.
    @Published var soundAutomatic: Bool {
        didSet { UserDefaults.standard.set(soundAutomatic, forKey: "soundAutomatic") }
    }

    var effectiveResolution: ResolutionChoice { displayAutomatic ? .windowed1080 : resolutionChoice }
    /// Device UID Play switches to; "" means keep the current output.
    var effectiveOutputUID: String { soundAutomatic ? "" : playOutputUID }
    /// Rate Play switches the output to; 0 leaves it alone.
    var effectiveRate: Double { soundAutomatic ? Store.automaticRate(for: playDevice) : playSampleRate }

    /// 96 kHz is the widely reported fix for the Mac game's crackling sound. Devices that
    /// can't reach it get their closest supported rate below it.
    static func automaticRate(for device: AudioOutput.Device?) -> Double {
        guard let device else { return 0 }
        if device.supportedRates.contains(96000) { return 96000 }
        return device.supportedRates.filter { $0 >= 44100 && $0 <= 96000 }.max() ?? 0
    }

    /// The device Play will use: the chosen one if connected, otherwise nil when one is
    /// chosen but missing, otherwise the current output.
    var playDevice: AudioOutput.Device? {
        effectiveOutputUID.isEmpty ? audioDevice : outputDevices.first { $0.uid == effectiveOutputUID }
    }
    var playDeviceMissing: Bool { !effectiveOutputUID.isEmpty && playDevice == nil }

    private var timer: Timer?
    private var wasRunning = false
    private var awaitingGameStart: Date?
    private var pendingDownloads: [String: Int64] = [:]
    private var checkedDownloads = Set<String>()
    private var importedDownloads: Set<String> {
        didSet { UserDefaults.standard.set(Array(importedDownloads.suffix(500)), forKey: "importedDownloads") }
    }

    init(paths: Paths = .standard) {
        self.paths = paths
        let d = UserDefaults.standard
        clearCachesOnPlay = d.bool(forKey: "clearCachesOnPlay")
        resolutionChoice = ResolutionChoice(rawValue: d.string(forKey: "resolution") ?? "") ?? .windowed1080
        // 96 kHz is the widely reported fix for the Mac game's crackling sound.
        playSampleRate = d.object(forKey: "playSampleRate") as? Double ?? 96000
        playOutputUID = d.string(forKey: "playOutputUID") ?? ""
        playOutputName = d.string(forKey: "playOutputName") ?? ""
        // People who already picked something keep it as a manual (Advanced) choice.
        displayAutomatic = d.object(forKey: "displayAutomatic") as? Bool
            ?? (d.string(forKey: "resolution").map { $0 == ResolutionChoice.windowed1080.rawValue } ?? true)
        soundAutomatic = d.object(forKey: "soundAutomatic") as? Bool
            ?? ((d.string(forKey: "playOutputUID") ?? "").isEmpty
                && (d.object(forKey: "playSampleRate") as? Double ?? 96000) == 96000)
        autoImportDownloads = d.object(forKey: "autoImportDownloads") as? Bool ?? true
        importedDownloads = Set(d.stringArray(forKey: "importedDownloads") ?? [])
        let device = SDDevice.all.first { $0.id == d.string(forKey: "deckDevice") } ?? SDDevice.detected() ?? SDDevice.all[0]
        deckDevice = device
        let savedLayout = (d.stringArray(forKey: "deckLayout") ?? []).compactMap(SDAction.init(rawValue:))
        deckLayout = savedLayout.isEmpty ? SDDevice.defaultLayout : savedLayout
        consoleUsesControl = d.bool(forKey: "consoleUsesControl")
        if d.object(forKey: "watchDownloadsSince") == nil { d.set(Date(), forKey: "watchDownloadsSince") }

        locateGame()
        refresh()
        wasRunning = gameRunning
        if !gameRunning { restoreAudio() }   // left over from a session that ended while we were closed
        refreshAudio()

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateRunning()
                self.refreshLaunchMode()   // notices if an EA app Repair switched it back
                self.refreshAudio()
                self.pollDownloads()
            }
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self, !self.gameRunning { self.restoreAudio() }
            }
        }
    }

    /// Shows the import section on the Home screen.
    func showImport() {
        pane = .play
        importExpanded = true
    }

    func updateVisibility() {
        let visible = NSApp.isActive && NSApp.windows.contains {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        }
        if visible != appVisible { appVisible = visible }
    }

    var hasModsFramework: Bool { FileManager.default.fileExists(atPath: paths.resourceCfg.path) }
    var activeCount: Int { mods.filter { $0.status == .active || $0.status == .override }.count }
    var disabledCount: Int { mods.filter { $0.status == .disabled }.count }
    var problemCount: Int { mods.filter { $0.status == .tooDeep || $0.status == .needsConversion }.count }

    // MARK: - scanning

    var userFolderMissing: Bool {
        !FileManager.default.fileExists(atPath: paths.user.path)
    }

    func refresh() {
        if userFolderMissing {
            notice = "Can't reach your Sims 3 folder (Documents/Electronic Arts). If it lives on an external drive, connect it and press Refresh."
        }
        var items: [ModItem] = []
        items += scan(paths.packages, area: .packages, disabled: false)
        items += scan(paths.overrides, area: .overrides, disabled: false)
        items += scan(paths.disabled.appendingPathComponent(ModArea.packages.rawValue), area: .packages, disabled: true)
        items += scan(paths.disabled.appendingPathComponent(ModArea.overrides.rawValue), area: .overrides, disabled: true)
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: paths.library, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        library = files.filter { $0.pathExtension.lowercased() == "package" }.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            return LibraryItem(url: url, size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate ?? .distantPast)
        }.sorted { $0.modified > $1.modified }
        items += library.map {
            ModItem(url: $0.url, area: .library, relPath: $0.url.lastPathComponent,
                    size: $0.size, modified: $0.modified, status: .inLibrary)
        }

        // Fill in type and friendly name from what's already been read; read the rest in
        // the background (it means opening each file, which takes a moment the first time).
        var missing: [ModItem] = []
        for i in items.indices {
            if let info = PackageInfo.cached(items[i].url, size: items[i].size, modified: items[i].modified) {
                items[i].kind = info.kind
                items[i].friendlyName = info.friendlyName
            } else {
                missing.append(items[i])
            }
        }
        mods = items.sorted {
            ($0.displayName.localizedLowercase, $0.folder) < ($1.displayName.localizedLowercase, $1.folder)
        }
        if !missing.isEmpty { analyze(missing) }
        updateRunning()
        refreshLaunchMode()
    }

    private func analyze(_ items: [ModItem]) {
        Task.detached(priority: .utility) {
            var results: [String: PackageInfo] = [:]
            for m in items {
                results[m.id] = PackageInfo.analyze(m.url, size: m.size, modified: m.modified,
                                                    library: m.area == .library)
            }
            let found = results
            await MainActor.run {
                self.mods = self.mods.map { m in
                    guard let info = found[m.id] else { return m }
                    var m = m
                    m.kind = info.kind
                    m.friendlyName = info.friendlyName
                    return m
                }.sorted {
                    ($0.displayName.localizedLowercase, $0.folder) < ($1.displayName.localizedLowercase, $1.folder)
                }
            }
        }
    }

    // MARK: - EA launch setting

    func refreshLaunchMode() {
        launchMode = gameURL.map { LaunchConfig.mode(of: LaunchConfig.file(forGame: $0)) } ?? .missing
    }

    func setLaunchMode(_ mode: LaunchConfig.Mode) {
        guard let game = gameURL else { return }
        do {
            try LaunchConfig.set(mode, file: LaunchConfig.file(forGame: game))
            notice = mode == .direct
                ? "Done. Play will go straight into the game from now on."
                : "Restored EA's original setting. The EA Launcher window will open again when you play."
        } catch {
            notice = error.localizedDescription
        }
        refreshLaunchMode()
    }

    private func scan(_ root: URL, area: ModArea, disabled: Bool) -> [ModItem] {
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        // ~/Documents/Electronic Arts is often a symlink to another drive, and the
        // enumerator hands back resolved paths, so compare resolved paths on both sides.
        let rootPath = root.resolvingSymlinksInPath().path + "/"
        var out: [ModItem] = []
        for case let url as URL in en {
            let ext = url.pathExtension.lowercased()
            guard ext == "package" || ext == "sims3pack" else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let full = url.resolvingSymlinksInPath().path
            let rel = full.hasPrefix(rootPath) ? String(full.dropFirst(rootPath.count)) : url.lastPathComponent
            let depth = rel.split(separator: "/").count - 1
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate ?? .distantPast
            let status: ModStatus
            if disabled {
                status = .disabled
            } else if ext == "sims3pack" {
                status = .needsConversion
            } else if depth > Store.maxDepth {
                status = .tooDeep
            } else {
                status = area == .overrides ? .override : .active
            }
            out.append(ModItem(url: url, area: area, relPath: rel, size: size, modified: modified, status: status))
        }
        return out
    }

    // MARK: - mod actions

    func setEnabled(_ items: [ModItem], _ enabled: Bool) {
        var failures: [String] = []
        var moved = 0
        for item in items {
            let activeRoot = item.area == .packages ? paths.packages : paths.overrides
            let disabledRoot = paths.disabled.appendingPathComponent(item.area.rawValue)
            let dest: URL
            if enabled {
                guard item.status == .disabled else { continue }
                dest = activeRoot.appendingPathComponent(item.relPath)
            } else {
                guard item.status != .disabled, item.status != .needsConversion, item.area != .library else { continue }
                dest = disabledRoot.appendingPathComponent(item.relPath)
            }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    failures.append("\(item.name): a file with that name is already there")
                    continue
                }
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: item.url, to: dest)
                removeEmptyFolders(from: item.url.deletingLastPathComponent(),
                                   upTo: enabled ? disabledRoot : activeRoot)
                moved += 1
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
            }
        }
        notice = failures.isEmpty
            ? "\(enabled ? "Enabled" : "Disabled") \(moved) item\(moved == 1 ? "" : "s")."
            : failures.joined(separator: "\n")
        refresh()
    }

    func moveToTrash(_ urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        notice = failures.isEmpty
            ? "Moved \(urls.count) item\(urls.count == 1 ? "" : "s") to the Trash."
            : failures.joined(separator: "\n")
        refresh()
    }

    /// Converts stray .sims3pack files sitting in Mods into .package files next to them,
    /// then moves the originals to the Trash.
    func convertInPlace(_ items: [ModItem]) {
        var out: [ImportResult] = []
        for item in items where item.status == .needsConversion {
            let r = Importer.installSims3Pack(item.url, label: item.name,
                                              modsDir: item.url.deletingLastPathComponent(), paths: paths)
            out.append(r)
            if r.ok { try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
        }
        results.insert(contentsOf: out, at: 0)
        let ok = out.filter(\.ok).count
        notice = "Converted \(ok) of \(out.count). Details are on the Import page."
        refresh()
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func removeEmptyFolders(from dir: URL, upTo root: URL) {
        let fm = FileManager.default
        var d = dir.resolvingSymlinksInPath()
        let stop = root.resolvingSymlinksInPath().path
        while d.path.hasPrefix(stop + "/") {
            let contents = (try? fm.contentsOfDirectory(atPath: d.path)) ?? ["?"]
            guard contents.allSatisfy({ $0 == ".DS_Store" }) else { break }
            try? fm.removeItem(at: d)
            d = d.deletingLastPathComponent()
        }
    }

    // MARK: - import

    func importItems(_ urls: [URL], fromDownloads: Bool = false) {
        guard !urls.isEmpty else { return }
        importing = true
        let paths = self.paths
        Task.detached(priority: .userInitiated) {
            let r = Importer.importItems(urls, paths: paths)
            await MainActor.run {
                self.results.insert(contentsOf: r, at: 0)
                self.importing = false
                self.refresh()
                if fromDownloads {
                    let ok = r.filter(\.ok).count
                    if ok > 0 {
                        self.notice = "Imported \(ok) new mod\(ok == 1 ? "" : "s") from your Downloads folder. Details are on the Import page."
                    }
                }
            }
        }
    }

    func chooseFilesToImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Import"
        panel.message = "Choose .package, .sims3pack or .zip files, or a folder of them."
        if panel.runModal() == .OK { importItems(panel.urls) }
    }

    // MARK: - caches

    var cacheSize: Int64 {
        Store.cacheFiles.reduce(0) { sum, f in
            let url = paths.user.appendingPathComponent(f)
            return sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    @discardableResult
    func clearCaches() -> Int64 {
        var freed: Int64 = 0
        for f in Store.cacheFiles {
            let url = paths.user.appendingPathComponent(f)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { freed += size }
        }
        notice = "Cleared caches (\(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))). The game rebuilds them on next launch."
        return freed
    }

    func createModsFramework() {
        let cfg = """
        Priority 500
        PackedFile DCCache/*.dbc
        PackedFile Packages/*.package
        PackedFile Packages/*/*.package
        PackedFile Packages/*/*/*.package
        PackedFile Packages/*/*/*/*.package
        PackedFile Packages/*/*/*/*/*.package
        Priority 1000
        PackedFile Overrides/*.package
        PackedFile Overrides/*/*.package
        PackedFile Overrides/*/*/*.package
        PackedFile Overrides/*/*/*/*.package
        PackedFile Overrides/*/*/*/*/*.package

        """
        do {
            try FileManager.default.createDirectory(at: paths.packages, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: paths.overrides, withIntermediateDirectories: true)
            try cfg.write(to: paths.resourceCfg, atomically: true, encoding: .utf8)
            notice = "Created the Mods folder and Resource.cfg."
        } catch {
            notice = error.localizedDescription
        }
        refresh()
    }

    // MARK: - game

    func locateGame() {
        if let saved = UserDefaults.standard.string(forKey: "gamePath"),
           FileManager.default.fileExists(atPath: saved) {
            gameURL = URL(fileURLWithPath: saved)
            return
        }
        if let found = spotlightFind(bundleID: Store.gameBundleID) {
            gameURL = found
            return
        }
        let fm = FileManager.default
        let volumes = (try? fm.contentsOfDirectory(atPath: "/Volumes")) ?? []
        var candidates = ["/Applications/Sims3Launcher.app", "/Applications/The Sims 3/Sims3Launcher.app"]
        for v in volumes {
            candidates.append("/Volumes/\(v)/Games/The Sims 3/Sims3Launcher.app")
            candidates.append("/Volumes/\(v)/The Sims 3/Sims3Launcher.app")
        }
        for c in candidates {
            let game = c + "/Contents/Resources/The Sims 3.app"
            if fm.fileExists(atPath: game) {
                gameURL = URL(fileURLWithPath: game)
                return
            }
        }
        gameURL = nil
    }

    private func spotlightFind(bundleID: String) -> URL? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["kMDItemCFBundleIdentifier == '\(bundleID)'"]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return out.split(separator: "\n").map(String.init)
            .first { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func chooseGame() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.prompt = "Use This Game"
        panel.message = "Choose \"The Sims 3.app\". It's inside Sims3Launcher.app → Contents → Resources."
        panel.treatsFilePackagesAsDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "gamePath")
            gameURL = url
        }
    }

    var gameMissingReason: String {
        if UserDefaults.standard.string(forKey: "gamePath") != nil {
            return "Can't find the game. Is the drive it lives on connected?"
        }
        return "Can't find The Sims 3. Use Locate Game to point to it."
    }

    func updateRunning() {
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Store.gameBundleID }
        gameRunning = running
        let quit = wasRunning && !running
        wasRunning = running
        if running { awaitingGameStart = nil }
        if quit {
            let fixes = guardFixes
            restoreAudio()
            if fixes > 0 {
                notice = "While you played, the sound output reset \(fixes) time\(fixes == 1 ? "" : "s") and was put back to your chosen setting."
            }
        } else if !running, let deadline = awaitingGameStart, Date() > deadline {
            // The game never started; don't leave the sound setting changed.
            awaitingGameStart = nil
            restoreAudio()
        }
    }

    // MARK: - launch settings

    /// Writes the chosen resolution into Options.ini and switches the output sample rate.
    private func applyLaunchSettings() {
        let ini = paths.user.appendingPathComponent("Options.ini")
        if effectiveResolution != .gameDefault, FileManager.default.fileExists(atPath: ini.path) {
            do { try OptionsIni.apply(effectiveResolution, to: ini) } catch {
                notice = "Couldn't set the resolution: \(error.localizedDescription)"
            }
        }
        if applyAudio() { startSoundGuard() }
        awaitingGameStart = Date().addingTimeInterval(180)
    }

    func refreshAudio() {
        audioDevice = AudioOutput.current()
        outputDevices = AudioOutput.outputDevices()
    }

    /// Switches to the chosen output device and sample rate, remembering what to put back.
    /// What's remembered is only ever added to, so pressing Play twice (or a session that
    /// ended while the app was closed) never loses the original settings.
    /// Returns true when the chosen sound settings are in force (so they should be guarded).
    @discardableResult
    func applyAudio() -> Bool {
        refreshAudio()
        guard let current = audioDevice else { return false }
        if playDeviceMissing {
            notice = "\(playOutputName.isEmpty ? "The chosen sound output" : playOutputName) isn't connected, so the sound was left as it is."
            return false
        }
        guard let target = playDevice else { return false }

        var restore = UserDefaults.standard.dictionary(forKey: "audioRestore") ?? [:]
        var rates = restore["rates"] as? [String: Double] ?? [:]
        if let uid = restore["uid"] as? String, let rate = restore["rate"] as? Double, rates[uid] == nil {
            rates[uid] = rate   // older single-device format
        }

        // A device that can't reach the rate wouldn't fix the crackle, so leave the sound
        // exactly as it is rather than switching halfway.
        if effectiveRate > 0, !target.supportedRates.contains(effectiveRate) {
            notice = "\(target.name) can't play at \(AudioOutput.label(effectiveRate)), so the sound was left as it is. Pick another device or rate in the sound menu."
            return false
        }
        if effectiveRate > 0, target.rate != effectiveRate {
            if target.supportedRates.contains(effectiveRate) {
                if rates[target.uid] == nil { rates[target.uid] = target.rate }
                restore["rates"] = rates
                UserDefaults.standard.set(restore, forKey: "audioRestore")   // save before changing anything
                if !AudioOutput.setRate(effectiveRate, on: target.id) {
                    notice = "Couldn't switch \(target.name) to \(AudioOutput.label(effectiveRate))."
                }
            } else {
                notice = "\(target.name) can't play at \(AudioOutput.label(effectiveRate)), so its sample rate was left at \(AudioOutput.label(target.rate))."
            }
        }
        if target.id != current.id {
            if restore["previousDefault"] == nil { restore["previousDefault"] = current.uid }
            restore["rates"] = rates
            UserDefaults.standard.set(restore, forKey: "audioRestore")
            if !AudioOutput.makeDefault(target.id) {
                notice = "Couldn't switch the sound output to \(target.name)."
            }
        }
        refreshAudio()
        return effectiveRate > 0 || !effectiveOutputUID.isEmpty
    }

    // MARK: - sound guard

    /// HDMI audio (a TV, for instance) can reset to its default 48 kHz when the game switches
    /// the screen mode at startup, and the game then opens its sound at the wrong rate. While
    /// the game starts and runs, keep the chosen device and rate in place.
    private var guardTimer: Timer?
    private(set) var guardFixes = 0

    func startSoundGuard() {
        stopSoundGuard()
        guardFixes = 0
        guardTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.guardTick() }
        }
    }

    func stopSoundGuard() {
        guardTimer?.invalidate()
        guardTimer = nil
    }

    private func guardTick() {
        // While the device is resetting it can vanish for a moment; just try again next tick.
        let target = effectiveOutputUID.isEmpty ? AudioOutput.current() : AudioOutput.device(uid: effectiveOutputUID)
        guard let target else { return }
        if !effectiveOutputUID.isEmpty, AudioOutput.current()?.uid != target.uid {
            if AudioOutput.makeDefault(target.id, wait: false) { guardFixes += 1 }
        }
        if effectiveRate > 0, target.rate != effectiveRate, target.supportedRates.contains(effectiveRate) {
            if AudioOutput.setRate(effectiveRate, on: target.id, wait: false) { guardFixes += 1 }
        }
    }

    /// Puts back the output device and sample rates from before Play was pressed.
    func restoreAudio() {
        stopSoundGuard()
        guard let saved = UserDefaults.standard.dictionary(forKey: "audioRestore") else { return }
        if let prev = saved["previousDefault"] as? String, let dev = AudioOutput.device(uid: prev),
           AudioOutput.current()?.uid != prev {
            _ = AudioOutput.makeDefault(dev.id)
        }
        var rates = saved["rates"] as? [String: Double] ?? [:]
        if let uid = saved["uid"] as? String, let rate = saved["rate"] as? Double { rates[uid] = rate }
        for (uid, rate) in rates {
            if let dev = AudioOutput.device(uid: uid), dev.rate != rate { _ = AudioOutput.setRate(rate, on: dev.id) }
        }
        UserDefaults.standard.removeObject(forKey: "audioRestore")
        refreshAudio()
    }

    // MARK: - Downloads folder

    private func pollDownloads() {
        guard autoImportDownloads, !importing, !screenshotMode else { return }
        let since = UserDefaults.standard.object(forKey: "watchDownloadsSince") as? Date ?? Date()
        var seenNow: [String: Int64] = [:]
        var ready: [URL] = []
        for c in DownloadScanner.newFiles(since: since) {
            if importedDownloads.contains(c.key) || checkedDownloads.contains(c.key) { continue }
            seenNow[c.url.path] = c.size
            // Same size as the last check means the download has finished.
            guard c.size > 0, pendingDownloads[c.url.path] == c.size else { continue }
            if DownloadScanner.isSims3Content(c.url) {
                ready.append(c.url)
                importedDownloads.insert(c.key)
            } else {
                checkedDownloads.insert(c.key)
            }
        }
        pendingDownloads = seenNow
        if !ready.isEmpty { importItems(ready, fromDownloads: true) }
    }

    func play() {
        if gameURL.map({ FileManager.default.fileExists(atPath: $0.path) }) != true { locateGame() }
        guard let app = gameURL else {
            notice = gameMissingReason
            return
        }
        if clearCachesOnPlay { clearCaches() }
        applyLaunchSettings()
        // EA app copies are started by the EA app, which checks the license and hands the
        // game a sign-in token. Ask it directly (the same request the game itself sends)
        // rather than opening the game and letting it bounce to the EA app.
        if let eaLaunch = URL(string: "origin2://game/launch/?offerIds=1092928"),
           NSWorkspace.shared.urlForApplication(toOpen: eaLaunch) != nil {
            NSWorkspace.shared.open(eaLaunch)
            notice = "Asked the EA app to start The Sims 3…"
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: app, configuration: cfg) { _, error in
            Task { @MainActor in
                if let error {
                    self.notice = "Couldn't start the game: \(error.localizedDescription)"
                } else {
                    self.notice = "Starting The Sims 3…"
                }
                self.updateRunning()
            }
        }
    }
}
