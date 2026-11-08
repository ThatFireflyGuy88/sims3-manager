import AppKit
import SwiftUI

// Command-line mode for testing the importer without the window:
//   Sims3Manager --check FILE...          show what an import would do (writes nothing)
//   Sims3Manager --import-to DIR FILE...  import into a scratch Sims 3 user folder
let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--check" {
    for path in args.dropFirst() {
        let url = URL(fileURLWithPath: path)
        do {
            let pack = try Sims3Pack(url: url)
            let parts = pack.entries.map { e -> String in
                let magic = pack.payload(of: e)?.magic ?? "????"
                return "\(e.contentType.isEmpty ? "?" : e.contentType)[\(magic)]"
            }
            print("\(url.lastPathComponent): type=\(pack.type) entries=\(parts.joined(separator: " "))")
        } catch {
            print("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
    exit(0)
}

if args.first == "--import-to", args.count >= 3 {
    let paths = Paths(user: URL(fileURLWithPath: args[1]))
    let files = args.dropFirst(2).map { URL(fileURLWithPath: $0) }
    for r in Importer.importItems(files, paths: paths) {
        print("\(r.ok ? "OK  " : "SKIP") \(r.source): \(r.message)")
    }
    exit(0)
}

// Exercises disable → enable → convert on a scratch user folder.
if args.first == "--selftest", args.count == 2 {
    MainActor.assumeIsolated {
        let store = Store(paths: Paths(user: URL(fileURLWithPath: args[1])))
        @MainActor func dump(_ title: String) {
            print("-- \(title): \(store.activeCount) active, \(store.disabledCount) disabled, \(store.problemCount) problems")
            for m in store.mods { print("   [\(m.status.label)] \(m.folder)/\(m.name)") }
        }
        dump("start")
        store.setEnabled(store.mods.filter { $0.folder.contains("Kitchen") && $0.status == .active }, false)
        print("   notice: \(store.notice ?? "")"); dump("after disable")
        store.setEnabled(store.mods.filter { $0.status == .disabled }, true)
        print("   notice: \(store.notice ?? "")"); dump("after enable")
        store.convertInPlace(store.mods.filter { $0.status == .needsConversion })
        print("   notice: \(store.notice ?? "")"); dump("after convert")
    }
    exit(0)
}

// --launch-mode FILE BACKUP show|direct|launcher   (for testing on a copy)
if args.first == "--launch-mode", args.count == 4 {
    let file = URL(fileURLWithPath: args[1]), backup = URL(fileURLWithPath: args[2])
    do {
        switch args[3] {
        case "direct": try LaunchConfig.set(.direct, file: file, backup: backup)
        case "launcher": try LaunchConfig.set(.launcher, file: file, backup: backup)
        default: break
        }
        print("mode: \(LaunchConfig.mode(of: file))")
    } catch {
        print("error: \(error.localizedDescription)")
    }
    exit(0)
}

// --test-settings OPTIONS_COPY.ini FILE...  exercises the Options.ini edit and content detection
if args.first == "--test-settings", args.count >= 2 {
    let ini = URL(fileURLWithPath: args[1])
    for choice in [ResolutionChoice.full1440, .windowed1080] {
        try? OptionsIni.apply(choice, to: ini)
        print("\(choice.label): resolution=\(OptionsIni.get("resolution", in: ini) ?? "?") fullscreen=\(OptionsIni.get("fullscreen", in: ini) ?? "?")")
    }
    for f in args.dropFirst(2) {
        let url = URL(fileURLWithPath: f)
        let why = url.pathExtension.lowercased() == "package" ? (Importer.sims3PackageProblem(url) ?? "ok") : ""
        print("\(url.lastPathComponent): sims3=\(DownloadScanner.isSims3Content(url)) \(why)")
    }
    exit(0)
}

// --audio-play-test UID RATE   does what Play does to the sound, then what quitting the game does
if args.first == "--audio-play-test", args.count == 3, let rate = Double(args[2]) {
    MainActor.assumeIsolated {
        func show(_ title: String) {
            let def = AudioOutput.current()
            print("\(title): output=\(def?.name ?? "?") | " + AudioOutput.outputDevices()
                .map { "\($0.name) \(AudioOutput.label($0.rate))" }.joined(separator: ", "))
        }
        UserDefaults.standard.removeObject(forKey: "audioRestore")
        let store = Store()
        store.playOutputUID = args[1]
        store.playOutputName = AudioOutput.device(uid: args[1])?.name ?? "?"
        store.playSampleRate = rate
        show("before ")
        store.applyAudio()
        show("playing")
        print("  saved to restore: \(UserDefaults.standard.dictionary(forKey: "audioRestore") ?? [:])")
        print("  notice: \(store.notice ?? "none")")
        store.restoreAudio()
        show("after  ")
    }
    exit(0)
}

// --guard-test UID RATE KNOCK_RATE   starts the sound guard, knocks the device to KNOCK_RATE
// (like an HDMI reset), and checks the guard puts RATE back
if args.first == "--guard-test", args.count == 4, let rate = Double(args[2]), let knock = Double(args[3]) {
    MainActor.assumeIsolated {
        UserDefaults.standard.removeObject(forKey: "audioRestore")
        let store = Store()
        store.playOutputUID = args[1]
        store.playSampleRate = rate
        print("apply: \(store.applyAudio())  device now \(AudioOutput.device(uid: args[1]).map { AudioOutput.label($0.rate) } ?? "?")")
        store.startSoundGuard()
        if let dev = AudioOutput.device(uid: args[1]) {
            print("knock to \(AudioOutput.label(knock)): \(AudioOutput.setRate(knock, on: dev.id))")
        }
        for i in 1...8 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            let r = AudioOutput.device(uid: args[1])?.rate ?? 0
            print("  t+\(Double(i) * 0.25)s: \(AudioOutput.label(r))  fixes=\(store.guardFixes)")
        }
        store.restoreAudio()
        print("after restore: \(AudioOutput.device(uid: args[1]).map { AudioOutput.label($0.rate) } ?? "?"), output=\(AudioOutput.current()?.name ?? "?")")
    }
    exit(0)
}

// --mod-names   reads every mod and prints its type and friendly name
if args.first == "--mod-names" {
    MainActor.assumeIsolated {
        let store = Store()
        let start = Date()
        var kinds: [String: Int] = [:]
        for m in store.mods {
            let info = PackageInfo.analyze(m.url, size: m.size, modified: m.modified, library: m.area == .library)
            kinds[info.kind.rawValue, default: 0] += 1
            print("\(info.kind.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)) \(info.friendlyName ?? "-")  [\(m.name)]")
        }
        print("--- \(store.mods.count) items in \(String(format: "%.2f", Date().timeIntervalSince(start)))s: \(kinds)")
    }
    exit(0)
}

// --deck-profile OUT   writes a Stream Deck profile with the default layout
// --deck-profile OUT [mac|windows] [MODEL]   (MODEL is a Stream Deck model code, e.g. 20GBJ9901)
if args.first == "--deck-profile", args.count >= 2 {
    MainActor.assumeIsolated {
        let store = Store()
        let platform: DeckPlatform = args.count > 2 && args[2].lowercased() == "windows" ? .windows : .mac
        let device = (args.count > 3 ? SDDevice.all.first { $0.id == args[3] } : nil)
            ?? SDDevice.detected() ?? SDDevice.all[0]
        do {
            try StreamDeckProfile.write(device: device, layout: SDDevice.defaultLayout, gameApp: store.gameURL,
                                        platform: platform, to: URL(fileURLWithPath: args[1]))
            print("wrote profile for \(device.name)")
        } catch { print("error: \(error)") }
    }
    exit(0)
}

// --screenshots DIR   saves pictures of the main screens (for the README)
if args.first == "--screenshots", args.count == 2 {
    MainActor.assumeIsolated { Screenshotter.run(to: URL(fileURLWithPath: args[1])) }
    exit(0)
}

if args.first == "--list-audio" {
    let def = AudioOutput.current()?.uid
    for d in AudioOutput.outputDevices() {
        print("\(d.uid == def ? "*" : " ") \(d.name) | \(AudioOutput.label(d.rate)) | supports \(d.supportedRates.map(AudioOutput.label).joined(separator: ", ")) | uid=\(d.uid)")
    }
    exit(0)
}

// --audio-roundtrip RATE   switches the output to RATE, reads it back, then restores it
if args.first == "--audio-roundtrip", args.count == 2, let rate = Double(args[1]) {
    guard let dev = AudioOutput.current() else { print("no output device"); exit(1) }
    print("device: \(dev.name) uid=\(dev.uid) rate=\(dev.rate) supported=\(dev.supportedRates)")
    func settle(_ target: Double) -> Double {
        for _ in 0..<20 {   // the change is applied asynchronously
            if let r = AudioOutput.current()?.rate, r == target { return r }
            usleep(100_000)
        }
        return AudioOutput.current()?.rate ?? 0
    }
    print("set \(rate): \(AudioOutput.setRate(rate, on: dev.id)) -> now \(settle(rate))")
    let back = AudioOutput.device(uid: dev.uid)
    print("lookup by uid: \(back?.name ?? "FAILED")")
    print("restore \(dev.rate): \(AudioOutput.setRate(dev.rate, on: back?.id ?? dev.id)) -> now \(settle(dev.rate))")
    exit(0)
}

// --render-play OUT.png   renders the Play screen to an image (for checking the design)
if args.first == "--render-play", args.count >= 2 {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let store = Store()
        let view = PlayView(snapshot: true)
            .environmentObject(store)
            .frame(width: 720, height: args.count > 2 ? CGFloat(Double(args[2]) ?? 760) : 760)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: args[1]))
            print("rendered")
        } else {
            print("render failed")
        }
    }
    exit(0)
}

if args.first == "--scan" {
    MainActor.assumeIsolated {
        let store = Store()
        print("game: \(store.gameURL?.path ?? "NOT FOUND")")
        print("Resource.cfg: \(store.hasModsFramework ? "present" : "missing")")
        print("mods: \(store.activeCount) active, \(store.disabledCount) disabled, \(store.problemCount) problems")
        for m in store.mods where m.status != .active {
            print("  [\(m.status.label)] \(m.folder)/\(m.name)")
        }
        print("library: \(store.library.map(\.name).joined(separator: ", "))")
        print("caches: \(formatBytes(store.cacheSize))")
    }
    exit(0)
}

Sims3ManagerApp.main()
