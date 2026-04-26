import Foundation

protocol MarkdownRenderer: Sendable {
  func render(_ source: String, baseURL: URL) async throws -> String
}

enum RendererError: LocalizedError {
  case executableNotFound(String)
  case nonZeroExit(code: Int32, stderr: String)

  var errorDescription: String? {
    switch self {
    case .executableNotFound(let path):
      return "Markdown processor not found at \(path)"
    case .nonZeroExit(let code, let stderr):
      return "Markdown processor exited with code \(code): \(stderr)"
    }
  }
}
