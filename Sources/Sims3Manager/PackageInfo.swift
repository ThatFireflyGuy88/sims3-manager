import Foundation

/// What kind of content a mod file holds, worked out from the resource types inside it.
enum ModKind: String {
    case script = "Script mod"
    case object = "Object"
    case cas = "Create-a-Sim"
    case build = "Build"
    case pattern = "Pattern"
    case tuning = "Tuning tweak"
    case replacement = "Replacement"
    case household = "Household"
    case lot = "Lot"
    case sims3pack = "Sims3Pack"
    case other = "Other"
    case unknown = "…"

    var icon: String {
        switch self {
        case .script: return "curlybraces"
        case .object: return "sofa"
        case .cas: return "tshirt"
        case .build: return "square.split.bottomrightquarter"
        case .pattern: return "paintpalette"
        case .tuning: return "slider.horizontal.3"
        case .replacement: return "arrow.triangle.swap"
        case .household: return "person.3"
        case .lot: return "house"
        case .sims3pack: return "shippingbox"
        case .other, .unknown: return "doc"
        }
    }
}

struct PackageInfo {
    let kind: ModKind
    let friendlyName: String?
    let itemCount: Int

    // Sims 3 resource types
    private static let script: UInt32 = 0x073F_AA07
    private static let objd: UInt32 = 0x319E_4F1D
    private static let casp: UInt32 = 0x034A_EECB
    private static let stbl: UInt32 = 0x2205_57DA
    private static let xml: UInt32 = 0x0333_406C
    private static let ptrn: UInt32 = 0xD4D9_FBE5
    private static let buildTypes: Set<UInt32> = [
        0x9151_E6BC, // walls
        0xB4F7_62C9, // floors
        0x0418_FE2A, // fences
        0x2FAE_983E, // foundations
        0x9A20_CD1C, // stairs
        0x04C5_8103, // railings
    ]
    private static let assetTypes: Set<UInt32> = [
        0x00B2_D882, // textures
        0x015A_1849, // GEOM
        0x01D1_0F34, // MLOD
        0x0166_1233, // MODL
        0x7368_84F1, // VPXY
        0x033A_1435, // TXTC
        0xB1CC_1AF6, // video
    ]
    private static let tuningTypes: Set<UInt32> = [
        0x0333_406C, // XML tuning
        0x03B3_3DDF, // interaction tuning
        0x0604_ABDA, // dream tree
        0x025C_95B6, // UI layout
    ]

    private struct Entry {
        let type: UInt32
        let instance: UInt64
        let offset: Int
        let size: Int
        let compressed: Bool
    }

    // MARK: cache

    private static var cache: [String: PackageInfo] = [:]
    private static let lock = NSLock()

    static func cached(_ url: URL, size: Int64, modified: Date) -> PackageInfo? {
        lock.lock(); defer { lock.unlock() }
        return cache[cacheKey(url, size, modified)]
    }

    static func analyze(_ url: URL, size: Int64, modified: Date, library: Bool) -> PackageInfo {
        let key = cacheKey(url, size, modified)
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let info = read(url, library: library)
        lock.lock(); cache[key] = info; lock.unlock()
        return info
    }

    private static func cacheKey(_ url: URL, _ size: Int64, _ modified: Date) -> String {
        "\(url.path)|\(size)|\(modified.timeIntervalSince1970)"
    }

    // MARK: reading

    private static func read(_ url: URL, library: Bool) -> PackageInfo {
        if url.pathExtension.lowercased() == "sims3pack" {
            return PackageInfo(kind: .sims3pack, friendlyName: prettify(url), itemCount: 0)
        }
        if library {
            let household = url.lastPathComponent.lowercased().hasPrefix("ebf_")
            let saved = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let date = saved.map { " (\($0.formatted(date: .abbreviated, time: .omitted)))" } ?? ""
            return PackageInfo(kind: household ? .household : .lot,
                               friendlyName: (household ? "Saved household" : "Saved lot") + date, itemCount: 1)
        }
        guard let h = try? FileHandle(forReadingFrom: url) else {
            return PackageInfo(kind: .other, friendlyName: prettify(url), itemCount: 0)
        }
        defer { try? h.close() }
        guard let entries = index(h), !entries.isEmpty else {
            return PackageInfo(kind: .other, friendlyName: prettify(url), itemCount: 0)
        }

        var counts: [UInt32: Int] = [:]
        for e in entries { counts[e.type, default: 0] += 1 }
        let objects = counts[objd] ?? 0
        let builds = buildTypes.reduce(0) { $0 + (counts[$1] ?? 0) }
        let kind: ModKind
        if counts[script] != nil { kind = .script }
        else if objects > 0 { kind = .object }
        else if counts[casp] != nil { kind = .cas }
        else if builds > 0 { kind = .build }
        else if counts[ptrn] != nil { kind = .pattern }
        else if assetTypes.contains(where: { counts[$0] != nil }) { kind = .replacement }
        else if tuningTypes.contains(where: { counts[$0] != nil }) { kind = .tuning }
        else { kind = .other }

        // Catalog items carry their in-game name in an English string table, alongside a
        // longer description, so the shortest string is the name.
        var name: String?
        let catalogItems = objects + builds
        if kind == .object || kind == .build || kind == .replacement {
            let tables = entries.filter { $0.type == stbl && $0.instance >> 56 == 0 && $0.size < 512 * 1024 }
            var strings: [String] = []
            for t in tables.prefix(4) { strings += stringTable(h, t) }
            let limit = kind == .replacement ? 4 : 8 + catalogItems * 4
            if !strings.isEmpty, strings.count <= limit {
                name = strings
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count >= 2 && $0.count <= 60 && !$0.contains("\n") }
                    .min { $0.count < $1.count }
            }
        }
        if let n = name, catalogItems > 1 { name = "\(n) + \(catalogItems - 1) more" }
        return PackageInfo(kind: kind, friendlyName: name ?? prettify(url), itemCount: max(catalogItems, 1))
    }

    private static func index(_ h: FileHandle) -> [Entry]? {
        guard let header = try? h.read(upToCount: 96), header.count == 96,
              header.prefix(4) == Data("DBPF".utf8) else { return nil }
        let count = Int(header.u32(at: 0x24))
        let size = Int(header.u32(at: 0x2C))
        var pos = Int(header.u32(at: 0x40))
        if pos == 0 { pos = Int(header.u32(at: 0x28)) }
        guard count > 0, count < 200_000, size > 4, size < 64 * 1024 * 1024 else { return [] }
        guard (try? h.seek(toOffset: UInt64(pos))) != nil,
              let d = try? h.read(upToCount: size), d.count == size else { return nil }

        let flags = d.u32(at: 0)
        var p = 4
        var constant: [Int: UInt32] = [:]
        for bit in 0..<3 where flags & (1 << bit) != 0 {
            guard p + 4 <= d.count else { return nil }
            constant[bit] = d.u32(at: p); p += 4
        }
        var out: [Entry] = []
        out.reserveCapacity(count)
        for _ in 0..<count {
            var tgi: [UInt32] = []
            for bit in 0..<3 {
                if let c = constant[bit] { tgi.append(c) } else {
                    guard p + 4 <= d.count else { return out }
                    tgi.append(d.u32(at: p)); p += 4
                }
            }
            guard p + 20 <= d.count else { return out }
            let instLo = d.u32(at: p), offset = d.u32(at: p + 4), fileSize = d.u32(at: p + 8)
            let compressed = UInt16(d[d.startIndex + p + 16]) | UInt16(d[d.startIndex + p + 17]) << 8
            p += 20
            out.append(Entry(type: tgi[0], instance: UInt64(tgi[2]) << 32 | UInt64(instLo),
                             offset: Int(offset), size: Int(fileSize & 0x7FFF_FFFF),
                             compressed: compressed == 0xFFFF))
        }
        return out
    }

    private static func stringTable(_ h: FileHandle, _ e: Entry) -> [String] {
        guard (try? h.seek(toOffset: UInt64(e.offset))) != nil,
              var raw = try? h.read(upToCount: e.size), raw.count == e.size else { return [] }
        if e.compressed { raw = refpack(raw) }
        // "STBL", version (1), 2 bytes, count (4), 6 bytes, then entries:
        // key (8), length in UTF-16 units (4), text.
        guard raw.count >= 17, raw.prefix(4) == Data("STBL".utf8) else { return [] }
        let count = Int(raw.u32(at: 7))
        var p = 17
        var out: [String] = []
        for _ in 0..<min(count, 10_000) {
            guard p + 12 <= raw.count else { break }
            let len = Int(raw.u32(at: p + 8))
            p += 12
            guard len >= 0, p + len * 2 <= raw.count else { break }
            let s = String(data: raw.subdata(in: (raw.startIndex + p)..<(raw.startIndex + p + len * 2)),
                           encoding: .utf16LittleEndian) ?? ""
            out.append(s)
            p += len * 2
        }
        return out
    }

    /// EA's RefPack (QFS) decompression.
    static func refpack(_ src: Data) -> Data {
        let s = [UInt8](src)
        guard s.count > 5, s[1] == 0xFB else { return src }
        let wide = s[0] & 0x80 != 0
        let n = wide ? 4 : 3
        var pos = 2 + (s[0] & 0x01 != 0 ? n : 0)
        var size = 0
        for i in 0..<n { size = size << 8 | Int(s[pos + i]) }
        pos += n
        var out = [UInt8]()
        out.reserveCapacity(size)
        while pos < s.count {
            let b0 = Int(s[pos])
            var plain = 0, copy = 0, off = 0
            if b0 < 0x80 {
                guard pos + 1 < s.count else { break }
                let b1 = Int(s[pos + 1])
                plain = b0 & 3; copy = ((b0 & 0x1C) >> 2) + 3; off = ((b0 & 0x60) << 3) + b1 + 1; pos += 2
            } else if b0 < 0xC0 {
                guard pos + 2 < s.count else { break }
                let b1 = Int(s[pos + 1]), b2 = Int(s[pos + 2])
                plain = (b1 >> 6) & 3; copy = (b0 & 0x3F) + 4; off = ((b1 & 0x3F) << 8) + b2 + 1; pos += 3
            } else if b0 < 0xE0 {
                guard pos + 3 < s.count else { break }
                let b1 = Int(s[pos + 1]), b2 = Int(s[pos + 2]), b3 = Int(s[pos + 3])
                plain = b0 & 3; copy = ((b0 & 0x0C) << 6) + b3 + 5
                off = ((b0 & 0x10) << 12) + (b1 << 8) + b2 + 1; pos += 4
            } else if b0 < 0xFC {
                plain = ((b0 & 0x1F) << 2) + 4; pos += 1
            } else {
                plain = b0 & 3; pos += 1
            }
            guard pos + plain <= s.count else { break }
            out.append(contentsOf: s[pos..<(pos + plain)]); pos += plain
            if copy > 0 {
                guard off <= out.count else { break }
                for _ in 0..<copy { out.append(out[out.count - off]) }
            }
            if b0 >= 0xFC { break }
        }
        return Data(out)
    }

    /// "NRaas_MasterController" → "NRaas Master Controller"
    static func prettify(_ url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        var out = ""
        var prev: Character?
        for ch in base {
            let c: Character = (ch == "_" || ch == "-") ? " " : ch
            if let p = prev, p.isLowercase, c.isUppercase { out.append(" ") }
            out.append(c)
            prev = c
        }
        return out.split(separator: " ").joined(separator: " ")
    }
}
