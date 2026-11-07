import AppKit
import SwiftUI

// MARK: - Keys

/// A key as Stream Deck stores it: the macOS key code, Qt's key code, and modifiers.
struct SDKey {
    let mac: Int
    let qt: Int
    var shift = false, ctrl = false, option = false, cmd = false

    var modifierMask: Int { (shift ? 1 : 0) | (ctrl ? 2 : 0) | (option ? 4 : 0) | (cmd ? 8 : 0) }

    static func letter(_ c: Character, mac: Int) -> SDKey { SDKey(mac: mac, qt: Int(c.asciiValue!)) }
    static let p = letter("P", mac: 35), n = letter("N", mac: 45), c = letter("C", mac: 8)
    static func digit(_ d: Int) -> SDKey { SDKey(mac: [29, 18, 19, 20, 21][d], qt: 48 + d) }
    static let space = SDKey(mac: 49, qt: 32)
    static let returnKey = SDKey(mac: 36, qt: 0x0100_0004)
    static let home = SDKey(mac: 115, qt: 0x0100_0010), end = SDKey(mac: 119, qt: 0x0100_0011)
    static let pageUp = SDKey(mac: 116, qt: 0x0100_0016), pageDown = SDKey(mac: 121, qt: 0x0100_0017)
    static let f1 = SDKey(mac: 122, qt: 0x0100_0030), f2 = SDKey(mac: 120, qt: 0x0100_0031)
    static let f3 = SDKey(mac: 99, qt: 0x0100_0032), f10 = SDKey(mac: 109, qt: 0x0100_0039)

    /// The cheat console: Cmd+Shift+C on the 64-bit Mac game (Ctrl+Shift+C on some setups).
    static func console(control: Bool) -> SDKey {
        SDKey(mac: 8, qt: 67, shift: true, ctrl: control, cmd: !control)
    }
}

/// How a button works on the Stream Deck itself; nothing needs Sims 3 Manager running.
enum DeckBehavior {
    /// Sends the same key every press.
    case keys([SDKey])
    /// Alternates between two keys (Stream Deck's Hotkey Switch).
    case toggle(SDKey, SDKey)
    /// Opens the cheat console and pastes a cheat, alternating between two
    /// (Stream Deck's Multi Action Switch).
    case cheats(String, String)
}

// MARK: - Actions

enum SDAction: String, CaseIterable, Identifiable {
    case none
    case pausePlay, speedCycle, pause, speed1, speed2, speed3
    case wallsNext, wallsPrevious, nextSim, centerSim
    case floorUp, floorDown, liveMode, buyMode, buildMode, hideUI, snapshot
    case moveObjects, testingCheats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Empty"
        case .pausePlay: return "Pause / Play"
        case .speedCycle: return "Change Speed"
        case .pause: return "Pause"
        case .speed1: return "Normal Speed"
        case .speed2: return "Fast"
        case .speed3: return "Ultra Fast"
        case .wallsNext: return "Wall Mode"
        case .wallsPrevious: return "Wall Mode Back"
        case .nextSim: return "Next Sim"
        case .centerSim: return "Find Sim"
        case .floorUp: return "Floor Up"
        case .floorDown: return "Floor Down"
        case .liveMode: return "Live Mode"
        case .buyMode: return "Buy Mode"
        case .buildMode: return "Build Mode"
        case .hideUI: return "Hide Interface"
        case .snapshot: return "Snapshot"
        case .moveObjects: return "Move Objects"
        case .testingCheats: return "Testing Cheats"
        }
    }

    /// Short label printed on the Stream Deck key.
    var keyTitle: String {
        switch self {
        case .pausePlay: return "Pause\nPlay"
        case .speedCycle: return "Speed"
        case .wallsNext: return "Walls"
        case .wallsPrevious: return "Walls ◀"
        case .nextSim: return "Next Sim"
        case .moveObjects: return "Move\nObjects"
        case .testingCheats: return "Testing\nCheats"
        case .hideUI: return "Hide UI"
        default: return title
        }
    }

    /// Titles for each state. Two-state buttons show what the next press will do.
    var stateTitles: (String, String) {
        switch self {
        case .pausePlay: return ("Pause", "Play")
        case .speedCycle: return ("Fast", "Ultra")
        case .moveObjects: return ("Move\nOn", "Move\nOff")
        default: return (keyTitle, keyTitle)
        }
    }

    var symbol: String {
        switch self {
        case .none: return "square.dashed"
        case .pausePlay: return "playpause.fill"
        case .speedCycle: return "forward.fill"
        case .pause: return "pause.fill"
        case .speed1: return "play.fill"
        case .speed2: return "forward.fill"
        case .speed3: return "forward.end.alt.fill"
        case .wallsNext: return "square.3.layers.3d.top.filled"
        case .wallsPrevious: return "square.3.layers.3d.bottom.filled"
        case .nextSim: return "person.2.fill"
        case .centerSim: return "scope"
        case .floorUp: return "arrow.up.square.fill"
        case .floorDown: return "arrow.down.square.fill"
        case .liveMode: return "figure.wave"
        case .buyMode: return "cart.fill"
        case .buildMode: return "hammer.fill"
        case .hideUI: return "eye.slash.fill"
        case .snapshot: return "camera.fill"
        case .moveObjects: return "arrow.up.and.down.and.arrow.left.and.right"
        case .testingCheats: return "wand.and.stars"
        }
    }

    var detail: String {
        switch self {
        case .none: return ""
        case .pausePlay: return "Pauses, and resumes at normal speed on the next press."
        case .speedCycle: return "Switches between fast and ultra fast."
        case .pause: return "Game key P."
        case .speed1, .speed2, .speed3: return "Game keys 1, 2 and 3."
        case .wallsNext: return "Next wall mode (Home key)."
        case .wallsPrevious: return "Previous wall mode (End key)."
        case .nextSim: return "Switches to the next Sim in the household (N key)."
        case .centerSim: return "Centres the camera on the active Sim (Return key)."
        case .floorUp, .floorDown: return "Page Up / Page Down."
        case .liveMode, .buyMode, .buildMode: return "F1, F2 and F3."
        case .hideUI: return "F10."
        case .snapshot: return "C key."
        case .moveObjects: return "Opens the cheat console and enters moveObjects on, then off on the next press."
        case .testingCheats: return "Opens the cheat console and enters testingCheatsEnabled true."
        }
    }

    var behavior: DeckBehavior? {
        switch self {
        case .none: return nil
        case .pausePlay: return .toggle(.p, .digit(1))          // pause, then resume at normal speed
        case .speedCycle: return .toggle(.digit(2), .digit(3))  // fast, then ultra fast
        case .pause: return .keys([.p])
        case .speed1: return .keys([.digit(1)])
        case .speed2: return .keys([.digit(2)])
        case .speed3: return .keys([.digit(3)])
        case .wallsNext: return .keys([.home])
        case .wallsPrevious: return .keys([.end])
        case .nextSim: return .keys([.n])
        case .centerSim: return .keys([.returnKey])
        case .floorUp: return .keys([.pageUp])
        case .floorDown: return .keys([.pageDown])
        case .liveMode: return .keys([.f1])
        case .buyMode: return .keys([.f2])
        case .buildMode: return .keys([.f3])
        case .hideUI: return .keys([.f10])
        case .snapshot: return .keys([.c])
        case .moveObjects: return .cheats("moveObjects on", "moveObjects off")
        case .testingCheats: return .cheats("testingCheatsEnabled true", "testingCheatsEnabled true")
        }
    }

    /// Two-state buttons, which flip between their states on each press.
    var isSwitch: Bool {
        switch behavior {
        case .toggle, .cheats: return true
        default: return false
        }
    }
}

// MARK: - Devices

struct SDDevice: Identifiable, Hashable {
    let id: String      // Stream Deck's model code
    let name: String
    let columns: Int
    let rows: Int
    let hasInfoBar: Bool

    static let all: [SDDevice] = [
        SDDevice(id: "20GBJ9901", name: "Stream Deck Neo", columns: 4, rows: 2, hasInfoBar: true),
        SDDevice(id: "20GAI9901", name: "Stream Deck Mini", columns: 3, rows: 2, hasInfoBar: false),
        SDDevice(id: "20GAA9902", name: "Stream Deck (15 keys)", columns: 5, rows: 3, hasInfoBar: false),
        SDDevice(id: "20GBD9901", name: "Stream Deck +", columns: 4, rows: 2, hasInfoBar: false),
        SDDevice(id: "20GAT9902", name: "Stream Deck XL", columns: 8, rows: 4, hasInfoBar: false),
    ]

    /// The model of the Stream Deck already set up on this Mac, if any.
    static func detected() -> SDDevice? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.elgato.StreamDeck/ProfilesV3")
        let profiles = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for p in profiles {
            guard let data = try? Data(contentsOf: p.appendingPathComponent("manifest.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let model = (json["Device"] as? [String: Any])?["Model"] as? String else { continue }
            if let d = all.first(where: { model.hasPrefix($0.id) }) { return d }
        }
        return nil
    }

    static let defaultLayout: [SDAction] = [
        .pausePlay, .speedCycle, .wallsNext, .nextSim,
        .liveMode, .buyMode, .buildMode, .moveObjects,
    ]
}

// MARK: - Profile file

enum StreamDeckProfile {
    /// Stream Deck names page and image folders with the ID in base 32 (0–9, A–T, V, W)
    /// followed by "Z".
    static func folderName(_ uuid: UUID = UUID()) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTVW")
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        var bits = bytes.map { String($0, radix: 2).leftPad(8) }.joined() + "00"
        var out = ""
        while !bits.isEmpty {
            let chunk = String(bits.prefix(5))
            bits = String(bits.dropFirst(5))
            out.append(alphabet[Int(chunk, radix: 2)!])
        }
        return out + "Z"
    }

    /// Writes a .streamDeckProfile (a zip that Stream Deck imports on double-click), in the
    /// same 3.0 layout Stream Deck uses for its own profiles. With `gameApp`, the profile is
    /// linked to the game so Stream Deck switches to it whenever the game is in front.
    static func write(device: SDDevice, layout: [SDAction], gameApp: URL?, consoleUsesControl: Bool = false,
                      to file: URL) throws {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("sdprofile-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        let profileDir = stage.appendingPathComponent("\(UUID().uuidString).sdProfile")
        let pageID = UUID(), defaultID = UUID()
        let pageDir = profileDir.appendingPathComponent("Profiles/\(pageID.uuidString)")
        let defaultDir = profileDir.appendingPathComponent("Profiles/\(defaultID.uuidString)")
        try fm.createDirectory(at: pageDir.appendingPathComponent("Images"), withIntermediateDirectories: true)
        try fm.createDirectory(at: defaultDir, withIntermediateDirectories: true)

        var actions: [String: Any] = [:]
        for (i, action) in layout.enumerated() where action != .none {
            let col = i % device.columns, row = i / device.columns
            guard row < device.rows else { break }
            guard let behavior = action.behavior else { continue }
            let image = "Images/\(folderName()).png"
            try ButtonIcon.png(for: action).write(to: pageDir.appendingPathComponent(image))
            let titles = action.stateTitles
            let key = "\(col),\(row)"
            switch behavior {
            case .keys(let keys):
                actions[key] = hotkeyAction(keys, states: [keyState(titles.0, image)])
            case .toggle(let first, let second):
                actions[key] = hotkeySwitchAction(first, second,
                                                  states: [keyState(titles.0, image), keyState(titles.1, image)])
            case .cheats(let first, let second):
                let console = SDKey.console(control: consoleUsesControl)
                actions[key] = multiActionSwitch(
                    [[hotkeyAction([console], states: [["Title": ""]], nested: true), pasteAction(first)],
                     [hotkeyAction([console], states: [["Title": ""]], nested: true), pasteAction(second)]],
                    states: [keyState(titles.0, image), keyState(titles.1, image)])
            }
        }

        var controllers: [[String: Any]] = [["Actions": actions, "Type": "Keypad"]]
        var defaultControllers: [[String: Any]] = [["Actions": [String: Any](), "Type": "Keypad"]]
        if device.hasInfoBar {
            controllers.append(["Actions": [String: Any](), "Type": "Neo"])
            defaultControllers.append(["Actions": ["1,0": [
                "ActionID": UUID().uuidString.lowercased(), "LinkedTitle": true, "Name": "Digital time",
                "Settings": ["24HourFormat": false, "layout": "digital_time_07", "location": "", "theme": "white"],
                "State": 0, "States": [[String: Any]()], "UUID": "com.elgato.streamdeck.system.digitaltime",
            ]], "Type": "Neo"])
        }
        try json(["Controllers": controllers, "Icon": "", "Name": ""], to: pageDir.appendingPathComponent("manifest.json"))
        try json(["Controllers": defaultControllers, "Icon": "", "Name": ""],
                 to: defaultDir.appendingPathComponent("manifest.json"))
        var top: [String: Any] = [
            "Device": ["Model": device.id, "UUID": ""],
            "Name": "The Sims 3",
            "Pages": ["Current": pageID.uuidString.lowercased(), "Default": defaultID.uuidString.lowercased(),
                      "Pages": [pageID.uuidString.lowercased()]],
            "Version": "3.0",
        ]
        if let gameApp { top["AppIdentifier"] = gameApp.path }
        try json(top, to: profileDir.appendingPathComponent("manifest.json"))

        try? fm.removeItem(at: file)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--norsrc", "--noextattr", stage.path, file.path]
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw CocoaError(.fileWriteUnknown) }
    }

    // The formats below copy buttons made in the Stream Deck app (Stream Deck 7.4).

    /// Up to four key presses, padded with empty slots the way Stream Deck stores them.
    private static func hotkeySlots(_ keys: [SDKey]) -> [[String: Any]] {
        var slots: [[String: Any]] = keys.prefix(4).map { k in
            ["KeyCmd": k.cmd, "KeyCtrl": k.ctrl, "KeyModifiers": k.modifierMask, "KeyOption": k.option,
             "KeyShift": k.shift, "NativeCode": k.mac, "QTKeyCode": k.qt, "VKeyCode": k.mac]
        }
        while slots.count < 4 {
            slots.append(["KeyCmd": false, "KeyCtrl": false, "KeyModifiers": 0, "KeyOption": false,
                          "KeyShift": false, "NativeCode": -1, "QTKeyCode": 33_554_431, "VKeyCode": -1])
        }
        return slots
    }

    private static func plugin(_ name: String, _ uuid: String) -> [String: Any] {
        ["Name": name, "UUID": uuid, "Version": "1.0"]
    }

    /// How a key looks in one state: its icon and the title printed under it.
    private static func keyState(_ title: String, _ image: String) -> [String: Any] {
        ["FontFamily": "", "FontSize": 11, "FontStyle": "", "FontUnderline": false,
         "Image": image, "OutlineThickness": 2, "ShowTitle": true, "Title": title,
         "TitleAlignment": "bottom", "TitleColor": "#ffffff"]
    }

    /// A plain Hotkey button, or (nested) a Hotkey step inside a Multi Action.
    private static func hotkeyAction(_ keys: [SDKey], states: [[String: Any]], nested: Bool = false) -> [String: Any] {
        var a: [String: Any] = [
            "ActionID": UUID().uuidString.lowercased(),
            "LinkedTitle": true,
            "Name": "Hotkey",
            "Settings": ["Coalesce": true, "Hotkeys": hotkeySlots(keys)],
            "State": 0,
            "States": states,
            "UUID": "com.elgato.streamdeck.system.hotkey",
        ]
        if nested {
            a["Plugin"] = plugin("Activate a Key Command", "com.elgato.streamdeck.system.hotkey")
            a["Resources"] = NSNull()
        }
        return a
    }

    /// Hotkey Switch: the first press sends `first`, the next sends `second`, and so on.
    private static func hotkeySwitchAction(_ first: SDKey, _ second: SDKey, states: [[String: Any]]) -> [String: Any] {
        [
            "ActionID": UUID().uuidString.lowercased(),
            "LinkedTitle": true,
            "Name": "Hotkey Switch",
            "Plugin": plugin("Hotkey Switch", "com.elgato.streamdeck.system.hotkeyswitch"),
            "Resources": NSNull(),
            "Settings": ["Coalesce": true, "Hotkeys": hotkeySlots([first, second])],
            "State": 0,
            "States": states,
            "UUID": "com.elgato.streamdeck.system.hotkeyswitch",
        ]
    }

    /// Text step that pastes `text` and presses Enter (the game's console accepts pasted text).
    private static func pasteAction(_ text: String) -> [String: Any] {
        [
            "ActionID": UUID().uuidString.lowercased(),
            "LinkedTitle": true,
            "Name": "Text",
            "Plugin": plugin("Text", "com.elgato.streamdeck.system.text"),
            "Resources": NSNull(),
            "Settings": [
                "Hotkey": ["KeyModifiers": 0, "QTKeyCode": 33_554_431, "VKeyCode": -1],
                "isSendingEnter": true,
                "isTypingMode": false,
                "pastedText": text,
            ],
            "State": 0,
            "States": [[String: Any]()],
            "UUID": "com.elgato.streamdeck.system.text",
        ]
    }

    /// Multi Action Switch: each press runs the next state's list of steps.
    private static func multiActionSwitch(_ steps: [[[String: Any]]], states: [[String: Any]]) -> [String: Any] {
        [
            "ActionID": UUID().uuidString.lowercased(),
            "Actions": steps.map { ["Actions": $0] },
            "LinkedTitle": true,
            "Name": "Multi Action Switch",
            "Plugin": plugin("Multi Action", "com.elgato.streamdeck.multiactions"),
            "Resources": NSNull(),
            "Settings": [String: Any](),
            "State": 0,
            "States": states,
            "UUID": "com.elgato.streamdeck.multiactions.routine2",
        ]
    }

    private static func json(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }
}

private extension String {
    func leftPad(_ n: Int) -> String { String(repeating: "0", count: max(0, n - count)) + self }
}

// MARK: - Key icons

enum ButtonIcon {
    /// 144×144 key image: the action's symbol in Sims green on a dark tile.
    static func png(for action: SDAction) -> Data {
        let px = 144
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: px, height: px)
        NSGradient(colors: [NSColor(calibratedRed: 0.05, green: 0.16, blue: 0.13, alpha: 1),
                            NSColor(calibratedRed: 0.01, green: 0.05, blue: 0.07, alpha: 1)])!
            .draw(in: rect, angle: -90)
        let config = NSImage.SymbolConfiguration(pointSize: 54, weight: .semibold)
            .applying(.init(paletteColors: [NSColor(calibratedRed: 0.42, green: 0.92, blue: 0.45, alpha: 1)]))
        if let sym = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let s = sym.size
            sym.draw(in: NSRect(x: (Double(px) - s.width) / 2, y: 62 - s.height / 2 + 16,
                                width: s.width, height: s.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
