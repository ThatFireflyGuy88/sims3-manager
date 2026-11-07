import Foundation

/// The EA app decides what to start from the <filePath> line in the Launcher bundle's
/// installerdata.xml. On a Mac it opens the app bundle named in brackets, after checking
/// the license and passing a sign-in token. Pointing it at the game's bundle instead of
/// the Launcher's skips the Launcher window; the license check is unchanged.
enum LaunchConfig {
    enum Mode { case direct, launcher, unknown, missing }

    static let launcherLine = "<filePath>[com.ea.mac.thesims3.launcher]/Contents/MacOS/The Sims 3 Launcher</filePath>"
    static let directLine = "<filePath>[com.ea.mac.thesims3.game]/Contents/MacOS/The Sims 3</filePath>"

    /// Game is …/Sims3Launcher.app/Contents/Resources/The Sims 3.app
    static func file(forGame game: URL) -> URL {
        game.deletingLastPathComponent()   // Resources
            .deletingLastPathComponent()   // Contents
            .appendingPathComponent("__Installer/installerdata.xml")
    }

    static func mode(of file: URL) -> Mode {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return .missing }
        if text.contains(directLine) { return .direct }
        if text.contains(launcherLine) { return .launcher }
        return .unknown
    }

    static func backupURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sims3Manager/installerdata.xml.orig")
    }

    /// Switches the launch target. Only the one known line is ever changed; anything
    /// unexpected is left alone. The first time the original is changed, a copy is saved.
    static func set(_ mode: Mode, file: URL, backup: URL = backupURL()) throws {
        var text = try String(contentsOf: file, encoding: .utf8)
        switch mode {
        case .direct:
            guard text.contains(launcherLine) else {
                if text.contains(directLine) { return }
                throw ConfigError.unrecognised
            }
            if !FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: file, to: backup)
            }
            text = text.replacingOccurrences(of: launcherLine, with: directLine)
        case .launcher:
            guard text.contains(directLine) else {
                if text.contains(launcherLine) { return }
                throw ConfigError.unrecognised
            }
            text = text.replacingOccurrences(of: directLine, with: launcherLine)
        case .unknown, .missing:
            return
        }
        // Overwrite in place so the file keeps its owner and permissions.
        try Data(text.utf8).write(to: file)
    }

    enum ConfigError: LocalizedError {
        case unrecognised
        var errorDescription: String? {
            "The EA launch setting isn't in a form this app recognises, so it was left unchanged."
        }
    }
}
