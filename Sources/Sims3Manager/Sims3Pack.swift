import Foundation

// A .sims3pack is a thin container:
//   [u32 magic length]["TS3Pack"][2 version bytes][u32 xml length][xml manifest][payloads...]
// Each <PackagedFile> in the manifest gives Name, Length, Offset (relative to the payload
// start) and ContentType. Modder content payloads are plain DBPF packages; EA Store
// content is encrypted (magic "DBPP") and cannot be used without EA's installer.

enum PackError: LocalizedError {
    case notSims3Pack
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .notSims3Pack: return "Not a .sims3pack file."
        case .malformed(let what): return "This .sims3pack is damaged (\(what))."
        }
    }
}

struct Sims3PackEntry {
    var name = ""
    var length = -1
    var offset = -1
    var contentType = ""
    var guid = ""
}

struct Sims3Pack {
    let url: URL
    let data: Data
    let payloadStart: Int
    var type = ""
    var displayName = ""
    var packageId = ""
    var entries: [Sims3PackEntry] = []

    init(url: URL) throws {
        self.url = url
        let d = try Data(contentsOf: url, options: .mappedIfSafe)
        guard d.count > 17, d.subdata(in: 4..<11) == Data("TS3Pack".utf8) else {
            throw PackError.notSims3Pack
        }
        let magicLen = Int(d.u32(at: 0))
        var pos = 4 + magicLen + 2
        guard pos + 4 <= d.count else { throw PackError.malformed("header") }
        let xmlLen = Int(d.u32(at: pos))
        pos += 4
        guard xmlLen > 0, pos + xmlLen <= d.count else { throw PackError.malformed("manifest") }
        let xml = d.subdata(in: pos..<(pos + xmlLen))
        self.data = d
        self.payloadStart = pos + xmlLen

        let delegate = ManifestParser()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse() else { throw PackError.malformed("manifest XML") }
        type = delegate.type
        displayName = delegate.displayName
        packageId = delegate.packageId
        entries = delegate.entries
    }

    func payload(of e: Sims3PackEntry) -> Data? {
        guard e.offset >= 0, e.length >= 0 else { return nil }
        let start = payloadStart + e.offset
        let end = start + e.length
        guard end <= data.count else { return nil }
        return data.subdata(in: start..<end)
    }
}

final class ManifestParser: NSObject, XMLParserDelegate {
    var type = ""
    var displayName = ""
    var packageId = ""
    var entries: [Sims3PackEntry] = []
    private var current: Sims3PackEntry?
    private var text = ""
    private var sawRoot = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        // The root element is usually <Sims3Package>, but challenge files use
        // <Sims3ChallengePackage>; either way the root carries the Type attribute.
        if !sawRoot {
            sawRoot = true
            type = attributes["Type"] ?? ""
        }
        if name == "PackagedFile" { current = Sims3PackEntry() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if var c = current {
            switch name {
            case "Name": c.name = t
            case "Length": c.length = Int(t) ?? -1
            case "Offset": c.offset = Int(t) ?? -1
            case "ContentType": c.contentType = t
            case "Guid": c.guid = t
            case "PackagedFile":
                entries.append(c)
                current = nil
                text = ""
                return
            default: break
            }
            current = c
        } else {
            switch name {
            case "DisplayName": displayName = t
            case "PackageId": packageId = t
            default: break
            }
        }
        text = ""
    }
}

extension Data {
    func u32(at offset: Int) -> UInt32 {
        var v: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &v) {
            copyBytes(to: $0, from: (startIndex + offset)..<(startIndex + offset + 4))
        }
        return UInt32(littleEndian: v)
    }

    var magic: String {
        String(decoding: prefix(4), as: UTF8.self)
    }
}
