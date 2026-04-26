import Foundation
import ALFoundation

/// Locate executables on the user's PATH by spawning a login shell.
/// Login shells source `~/.zshrc`, `~/.bash_profile`, etc., so this
/// finds tools the user can run from Terminal even if they are in
/// non-standard locations like Homebrew on Apple Silicon.
enum ShellLookup {
  static func locate(_ tool: String) async -> String? {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
    let streams = ProcessStreams.inMemory.memorizedError()

    let result: Process.ProcessResult
    do {
      result = try await Process.runAndCapture(
        URL(fileURLWithPath: shell),
        with: "-l", "-c", "command -v '\(tool)'",
        streams: streams)
    } catch {
      return nil
    }
    guard result.terminationStatus == 0 else { return nil }

    // Login-shell init files can echo banners. Pick the last absolute
    // path-looking line.
    let path = result.output
      .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
      .map(String.init)
      .last { $0.hasPrefix("/") }

    return path
  }
}
