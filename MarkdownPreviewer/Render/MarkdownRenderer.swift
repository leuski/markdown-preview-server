import Foundation

protocol MarkdownRenderer: Sendable {
  /// Stable identifier persisted across launches (e.g. "multimarkdown").
  var id: String { get }
  /// Human-readable name for menus and pickers (e.g. "MultiMarkdown 6").
  var displayName: String { get }
  /// Convert markdown source to an HTML body fragment.
  func render(_ source: String, baseURL: URL) async throws -> String
}

enum RendererError: LocalizedError {
  case executableNotFound(name: String)
  case nonZeroExit(code: Int32, stderr: String)

  var errorDescription: String? {
    switch self {
    case .executableNotFound(let name):
      return "\(name) not found on PATH"
    case .nonZeroExit(let code, let stderr):
      return "Markdown processor exited with code \(code): \(stderr)"
    }
  }
}
