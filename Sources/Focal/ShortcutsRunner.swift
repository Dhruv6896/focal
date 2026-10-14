import Foundation

/// Runs the user's macOS Shortcuts (e.g. one that turns on Do Not Disturb) via the
/// `shortcuts` command-line tool.
enum ShortcutsRunner {
    private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// Names of all shortcuts in the user's library, sorted.
    static func list() async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = tool
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }.value
    }

    /// Runs a shortcut in the background without waiting for it.
    static func run(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let process = Process()
        process.executableURL = tool
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("Focal: couldn't run shortcut \(name): \(error.localizedDescription)")
        }
    }
}
