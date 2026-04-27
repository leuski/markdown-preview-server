import Foundation
import ALFoundation

enum ScriptInstaller {
  enum InstallError: LocalizedError {
    case sourceMissing
    case copyFailed(URL, any Error)

    var errorDescription: String? {
      switch self {
      case .sourceMissing:
        "The bundled Scripts folder is missing from the application."
      case .copyFailed(let url, let error):
        "Failed to install \(url.lastPathComponent): \(error.localizedDescription)"
      }
    }
  }

  static var bundledSourceURL: URL? {
    Bundle.main.url(forResource: "Scripts", withExtension: nil)
  }

  static var defaultBBEditDestination: URL {
    URL.applicationSupportDirectory/"BBEdit"/"Scripts"
  }

  /// Copies the bundled Scripts folder into `destination`, customizing the
  /// hardcoded loopback port in shell scripts to match the running server.
  /// Files at the destination with the same relative path are overwritten.
  static func install(to destination: URL, port: UInt16) throws {
    guard let source = bundledSourceURL, source.itemExists else {
      throw InstallError.sourceMissing
    }

    try destination.createDirectory()

    let walker = source.enumerator(
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles, .producesRelativePathURLs])

    for url in walker {
      let target = destination.appending(path: url.relativePath)

      do {
        try installFile(from: url, to: target, port: port)
      } catch {
        throw InstallError.copyFailed(url, error)
      }
    }
  }

  private static func installFile(
    from source: URL, to target: URL, port: UInt16
  ) throws {
    try target.parent.createDirectory()

    if isShellScript(source) {
      let original = try String(contentsOf: source, encoding: .utf8)
      let customized = customize(script: original, port: port)
      try? target.remove()
      try customized.write(to: target, atomically: true, encoding: .utf8)
      try target.setPosixPermissions(0o755)
    } else {
      try source.copy(to: target, overwrite: true)
    }
  }

  private static func isShellScript(_ url: URL) -> Bool {
    ["sh", "bash", "zsh", "command"].contains(url.pathExtension.lowercased())
  }

  /// Replaces the loopback host:port literal embedded in bundled scripts so
  /// the installed copy targets the user's currently configured port.
  static func customize(script: String, port: UInt16) -> String {
    script.replacingOccurrences(
      of: "__LOCATION__",
      with: "http://\(AppModel.defaultHost):\(port)/preview")
  }
}
