import CoreAudio
import Foundation

// MARK: - Resolution

/// The game can't draw at Retina resolution itself, so on a scaled display it renders at
/// the "looks like" size and macOS stretches it. Fullscreen at a higher resolution makes
/// the game switch the display to that mode and draw that many real pixels.
enum ResolutionChoice: String, CaseIterable, Identifiable {
    case gameDefault, windowed1080, full1080, full1440, full2160

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gameDefault: return "Use the game's setting"
        case .windowed1080: return "1920 × 1080 window"
        case .full1080: return "1920 × 1080 fullscreen"
        case .full1440: return "2560 × 1440 fullscreen (clicks may miss)"
        case .full2160: return "3840 × 2160 fullscreen"
        }
    }

    var short: String {
        switch self {
        case .gameDefault: return "Game setting"
        case .windowed1080: return "1080p window"
        case .full1080: return "1080p"
        case .full1440: return "1440p"
        case .full2160: return "4K"
        }
    }

    var settings: (width: Int, height: Int, fullscreen: Bool)? {
        switch self {
        case .gameDefault: return nil
        case .windowed1080: return (1920, 1080, false)
        case .full1080: return (1920, 1080, true)
        case .full1440: return (2560, 1440, true)
        case .full2160: return (3840, 2160, true)
        }
    }
}

enum OptionsIni {
    /// Sets keys in the game's Options.ini ("key = value" lines), keeping every other line.
    static func set(_ values: [String: String], in file: URL) throws {
        var text = try String(contentsOf: file, encoding: .utf8)
        for (key, value) in values {
            let pattern = "(?m)^\(NSRegularExpression.escapedPattern(for: key))\\s*=.*$"
            let re = try NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..., in: text)
            let line = "\(key) = \(value)"
            if re.firstMatch(in: text, range: range) != nil {
                text = re.stringByReplacingMatches(in: text, range: range,
                                                   withTemplate: NSRegularExpression.escapedTemplate(for: line))
            } else {
                if !text.hasSuffix("\n") { text += "\n" }
                text += "\n\(line)\n"
            }
        }
        try Data(text.utf8).write(to: file)
    }

    static func get(_ key: String, in file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func apply(_ choice: ResolutionChoice, to file: URL) throws {
        guard let s = choice.settings else { return }
        try set(["resolution": "\(s.width) \(s.height) 0",
                 "fullscreen": s.fullscreen ? "1" : "0"], in: file)
    }
}

// MARK: - Audio output sample rate

/// The 64-bit Mac game's audio crackles at some output sample rates. Sims 3 Manager can
/// switch the current output device to a chosen rate while the game runs and put the
/// original rate back afterwards.
enum AudioOutput {
    struct Device {
        let id: AudioObjectID
        let uid: String
        let name: String
        let rate: Double
        let supportedRates: [Double]
    }

    static func current() -> Device? {
        var dev = AudioObjectID(0)
        guard get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &dev),
              dev != 0 else { return nil }
        return device(dev)
    }

    static func device(uid: String) -> Device? {
        var cfUID = uid as CFString
        var dev = AudioObjectID(0)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                       UInt32(MemoryLayout<CFString>.size), uidPtr, &size, &dev)
        }
        guard status == noErr, dev != 0 else { return nil }
        return device(dev)
    }

    /// Every device that can play sound, in the order macOS lists them.
    static func outputDevices() -> [Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasOutput).compactMap(device)
    }

    /// Makes `dev` the Mac's sound output.
    static func makeDefault(_ dev: AudioObjectID, wait: Bool = true) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var d = dev
        guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                         UInt32(MemoryLayout<AudioObjectID>.size), &d) == noErr else { return false }
        if !wait { return true }
        for _ in 0..<15 {   // applied asynchronously, like the sample rate
            if current()?.id == dev { return true }
            usleep(100_000)
        }
        return false
    }

    private static func hasOutput(_ dev: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                              mScope: kAudioObjectPropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        return AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr && size > 0
    }

    /// `wait: false` returns as soon as the change is requested (used by the in-game guard,
    /// which checks again a moment later anyway).
    static func setRate(_ rate: Double, on dev: AudioObjectID, wait: Bool = true) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var r = rate
        guard AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &r) == noErr else {
            return false
        }
        if !wait { return true }
        // CoreAudio applies the change asynchronously. Wait for it, so a later change
        // (like putting the old rate back) can't be applied before this one.
        for _ in 0..<15 {
            var now = Float64(0)
            if get(dev, kAudioDevicePropertyNominalSampleRate, &now), now == rate { return true }
            usleep(100_000)
        }
        return false
    }

    static func label(_ rate: Double) -> String {
        let k = rate / 1000
        return k == k.rounded() ? "\(Int(k)) kHz" : String(format: "%.1f kHz", k)
    }

    private static func device(_ dev: AudioObjectID) -> Device? {
        var rate = Float64(0)
        guard get(dev, kAudioDevicePropertyNominalSampleRate, &rate) else { return nil }
        return Device(id: dev, uid: string(dev, kAudioDevicePropertyDeviceUID) ?? "",
                      name: string(dev, kAudioObjectPropertyName) ?? "Output",
                      rate: rate, supportedRates: rates(dev))
    }

    private static func rates(_ dev: AudioObjectID) -> [Double] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(),
                                       count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &ranges) == noErr else { return [] }
        let common: [Double] = [32000, 44100, 48000, 88200, 96000, 176400, 192000]
        var out = Set<Double>()
        for r in ranges {
            for c in common where c >= r.mMinimum && c <= r.mMaximum { out.insert(c) }
        }
        return out.sorted()
    }

    private static func get<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, $0)
        } == noErr
    }

    private static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value) == noErr,
              let v = value?.takeRetainedValue() else { return nil }
        return v as String
    }
}

// MARK: - Downloads folder

/// Finds Sims 3 mods that land in ~/Downloads (for example from Nexus Mods or Mod The Sims).
enum DownloadScanner {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    struct Candidate: Hashable {
        let url: URL
        let size: Int64
        var key: String { "\(url.path)|\(size)" }
    }

    /// Finished files added to Downloads after `since`. Browsers' partial downloads
    /// (.download, .crdownload, .part) are skipped until they complete.
    static func newFiles(since: Date) -> [Candidate] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey, .fileSizeKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return files.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard ["package", "sims3pack", "zip"].contains(ext) else { return nil }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
            let added = v.addedToDirectoryDate ?? v.creationDate ?? .distantPast
            guard added >= since else { return nil }
            return Candidate(url: url, size: Int64(v.fileSize ?? 0))
        }
    }

    /// True when the file is Sims 3 content (or a zip containing some).
    static func isSims3Content(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "sims3pack":
            return true
        case "package":
            return Importer.sims3PackageProblem(url) == nil
        case "zip":
            let p = Process()
            let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
            p.arguments = ["-1", url.path]
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return false }
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            return out.split(separator: "\n").contains { line in
                let l = line.lowercased()
                return !l.contains("__macosx/") && (l.hasSuffix(".package") || l.hasSuffix(".sims3pack"))
            }
        default:
            return false
        }
    }
}
