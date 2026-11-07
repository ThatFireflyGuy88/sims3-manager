import Foundation

struct Paths {
    let user: URL
    var mods: URL { user.appendingPathComponent("Mods") }
    var packages: URL { mods.appendingPathComponent("Packages") }
    var overrides: URL { mods.appendingPathComponent("Overrides") }
    var disabled: URL { mods.appendingPathComponent("Disabled") }
    var library: URL { user.appendingPathComponent("Library") }
    var worlds: URL { user.appendingPathComponent("InstalledWorlds") }
    var resourceCfg: URL { mods.appendingPathComponent("Resource.cfg") }

    static let standard = Paths(user: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Electronic Arts/The Sims 3"))
}

struct ImportResult: Identifiable {
    let id = UUID()
    let source: String
    let ok: Bool
    let message: String
}

enum Importer {
    static let libraryTypes: Set<String> = [
        "household", "lot", "sim", "residentiallot", "communitylot", "apartmentlot",
    ]

    /// Import files and folders dropped on the app. Folders and zips are unpacked;
    /// when they hold several loose .package files, those go in a subfolder named
    /// after the folder/zip so they stay grouped.
    static func importItems(_ urls: [URL], paths: Paths) -> [ImportResult] {
        var results: [ImportResult] = []
        for url in urls {
            results += importItem(url, paths: paths)
        }
        return results
    }

    static func importItem(_ url: URL, paths: Paths) -> [ImportResult] {
        let name = url.lastPathComponent
        if isDirectory(url) {
            return importFolder(url, group: name, paths: paths)
        }
        switch url.pathExtension.lowercased() {
        case "package":
            return [installPackage(url, label: name, subfolder: nil, paths: paths)]
        case "sims3pack":
            return [installSims3Pack(url, label: name, modsDir: nil, paths: paths)]
        case "zip":
            return importZip(url, paths: paths)
        case "rar", "7z":
            return [ImportResult(source: name, ok: false,
                                 message: "Unpack this archive in Finder first, then import what's inside.")]
        default:
            return [ImportResult(source: name, ok: false, message: "Not Sims 3 content.")]
        }
    }

    static func importFolder(_ dir: URL, group: String, paths: Paths) -> [ImportResult] {
        let files = importableFiles(in: dir)
        if files.isEmpty {
            return [ImportResult(source: group, ok: false, message: "No .package or .sims3pack files inside.")]
        }
        let looseCount = files.filter { $0.pathExtension.lowercased() == "package" }.count
        let sub = looseCount > 1 ? sanitize(group) : nil
        var out: [ImportResult] = []
        for f in files {
            let label = group + " › " + f.lastPathComponent
            if f.pathExtension.lowercased() == "package" {
                out.append(installPackage(f, label: label, subfolder: sub, paths: paths))
            } else {
                out.append(installSims3Pack(f, label: label, modsDir: nil, paths: paths))
            }
        }
        return out
    }

    static func importZip(_ zip: URL, paths: Paths) -> [ImportResult] {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sims3Manager-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zip.path, tmp.path]
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                return [ImportResult(source: zip.lastPathComponent, ok: false, message: "Couldn't unzip this file.")]
            }
        } catch {
            return [ImportResult(source: zip.lastPathComponent, ok: false, message: error.localizedDescription)]
        }
        return importFolder(tmp, group: zip.deletingPathExtension().lastPathComponent, paths: paths)
    }

    static func importableFiles(in dir: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let f as URL in en {
            if f.path.contains("/__MACOSX/") || f.lastPathComponent.hasPrefix("._") { continue }
            let ext = f.pathExtension.lowercased()
            if ext == "package" || ext == "sims3pack" { out.append(f) }
        }
        return out.sorted { $0.path < $1.path }
    }

    // MARK: - .package

    static func installPackage(_ src: URL, label: String, subfolder: String?, paths: Paths) -> ImportResult {
        do {
            let data = try Data(contentsOf: src, options: .mappedIfSafe)
            if let problem = sims3PackageProblem(data) {
                return ImportResult(source: label, ok: false, message: problem)
            }
            var dir = paths.packages
            if let sub = subfolder { dir.appendPathComponent(sub) }
            let (dest, existed) = try place(data, name: src.lastPathComponent, in: dir)
            return ImportResult(source: label, ok: true,
                                message: existed ? "Already installed." : "Installed to \(describe(dest, paths: paths)).")
        } catch {
            return ImportResult(source: label, ok: false, message: error.localizedDescription)
        }
    }

    /// nil when the data is a Sims 3 package; otherwise why it isn't. Sims 3 packages are
    /// DBPF version 2.0; Sims 4 uses the same extension with DBPF 2.1.
    static func sims3PackageProblem(_ data: Data) -> String? {
        switch data.magic {
        case "DBPF":
            guard data.count >= 12 else { return "Not a valid Sims 3 package." }
            let major = data.u32(at: 4), minor = data.u32(at: 8)
            if major == 2 && minor == 1 { return "This is a Sims 4 mod, not Sims 3." }
            if major == 2 && minor == 0 { return nil }
            return "Not a Sims 3 package (DBPF \(major).\(minor))."
        case "DBPP":
            return "Encrypted EA Store package; it can't be installed on a Mac."
        default:
            return "Not a valid Sims 3 package."
        }
    }

    static func sims3PackageProblem(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "Can't read this file." }
        defer { try? h.close() }
        return sims3PackageProblem(h.readData(ofLength: 12))
    }

    // MARK: - .sims3pack

    /// `modsDir` overrides where object/CAS packages go (used to convert a stray
    /// .sims3pack in place inside the Mods folder).
    static func installSims3Pack(_ src: URL, label: String, modsDir: URL?, paths: Paths) -> ImportResult {
        let pack: Sims3Pack
        do { pack = try Sims3Pack(url: src) } catch {
            return ImportResult(source: label, ok: false, message: error.localizedDescription)
        }
        let rootType = pack.type.lowercased()
        if rootType == "dynamicchallenge"
            || pack.entries.contains(where: { $0.contentType.lowercased() == "dynamicchallenge" }) {
            return ImportResult(source: label, ok: false,
                                message: "Old Sims 3 Exchange challenge file. It isn't game content.")
        }

        var parts: [(Sims3PackEntry, Data)] = []
        var encrypted = false
        for e in pack.entries {
            guard let blob = pack.payload(of: e) else {
                return ImportResult(source: label, ok: false, message: PackError.malformed("file table").localizedDescription)
            }
            switch blob.magic {
            case "DBPF": parts.append((e, blob))
            case "DBPP": encrypted = true
            default: break // thumbnails and similar
            }
        }
        if encrypted {
            return ImportResult(source: label, ok: false,
                                message: "Encrypted EA Store content. It can only be installed with EA's tools, which don't work on this Mac.")
        }
        if parts.isEmpty {
            return ImportResult(source: label, ok: false, message: "No game content inside.")
        }

        let base = sanitize(src.deletingPathExtension().lastPathComponent)
        enum Kind { case world, library, mod }
        func kind(_ e: Sims3PackEntry) -> Kind {
            let ct = e.contentType.lowercased()
            if ct == "world" || e.name.lowercased().hasSuffix(".world") { return .world }
            if libraryTypes.contains(ct) { return .library }
            if libraryTypes.contains(rootType),
               parts.count == 1 || e.guid.lowercased() == pack.packageId.lowercased() { return .library }
            return .mod
        }
        let kinds = parts.map { kind($0.0) }
        let modCount = kinds.filter { $0 == .mod }.count
        let worldCount = kinds.filter { $0 == .world }.count
        let libCount = kinds.filter { $0 == .library }.count

        var placed: [String] = []
        var already = 0
        var modIndex = 0, worldIndex = 0, libIndex = 0
        do {
            for (i, (_, blob)) in parts.enumerated() {
                let dest: (URL, Bool)
                switch kinds[i] {
                case .world:
                    worldIndex += 1
                    let name = worldCount == 1 ? "\(base).world" : "\(base) (\(worldIndex)).world"
                    dest = try place(blob, name: name, in: paths.worlds)
                case .library:
                    libIndex += 1
                    let name = libCount == 1 ? "\(base).package" : "\(base) (\(libIndex)).package"
                    dest = try place(blob, name: name, in: paths.library)
                case .mod:
                    modIndex += 1
                    var dir = modsDir ?? paths.packages
                    let name: String
                    if modCount == 1 {
                        name = "\(base).package"
                    } else {
                        if modsDir == nil { dir.appendPathComponent(base) }
                        name = "\(base) (\(modIndex)).package"
                    }
                    dest = try place(blob, name: name, in: dir)
                }
                if dest.1 { already += 1 }
                placed.append(describe(dest.0, paths: paths))
            }
        } catch {
            return ImportResult(source: label, ok: false, message: error.localizedDescription)
        }

        if already == parts.count {
            return ImportResult(source: label, ok: true, message: "Already installed.")
        }
        var summary: [String] = []
        if worldCount > 0 { summary.append("world → InstalledWorlds") }
        if libCount > 0 { summary.append(libCount == 1 ? "lot/household → Library" : "\(libCount) lots/households → Library") }
        if modCount > 0 {
            let where_ = modsDir.map { describe($0, paths: paths) } ?? (modCount == 1 ? "Mods/Packages" : "Mods/Packages/\(base)")
            summary.append(modCount == 1 ? "1 package → \(where_)" : "\(modCount) packages → \(where_)")
        }
        return ImportResult(source: label, ok: true, message: "Installed: " + summary.joined(separator: ", ") + ".")
    }

    // MARK: - helpers

    /// Writes `data` as `name` in `dir`. If an identical file is already there, nothing is
    /// written; if a different file has that name, a numbered name is used instead.
    static func place(_ data: Data, name: String, in dir: URL) throws -> (URL, Bool) {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var candidate = dir.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            if let existing = try? Data(contentsOf: candidate, options: .mappedIfSafe), existing == data {
                return (candidate, true)
            }
            candidate = dir.appendingPathComponent("\(stem) (\(n)).\(ext)")
            n += 1
        }
        try data.write(to: candidate, options: .atomic)
        return (candidate, false)
    }

    static func describe(_ url: URL, paths: Paths) -> String {
        let p = url.path
        let root = paths.user.path + "/"
        return p.hasPrefix(root) ? String(p.dropFirst(root.count)) : p
    }

    static func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:")
        return s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
