import Foundation
import ALFoundation

struct MultiMarkdownRenderer: MarkdownRenderer {
  static let toolName = "multimarkdown"

  let id = "multimarkdown"
  let displayName = "MultiMarkdown"

  let executableURL: URL

  /// Locate the executable via the user's login shell so PATH from
  /// `~/.zshrc`/`~/.bash_profile` is honoured. Returns `nil` if the tool
  /// is not installed.
  static func discover() async -> MultiMarkdownRenderer? {
    guard let url = try? await URL(command: toolName), url.isExecutable
    else { return nil }
    return MultiMarkdownRenderer(executableURL: url)
  }

  func render(_ source: String, baseURL: URL) async throws -> String {
    guard executableURL.isExecutable else {
      throw RendererError.executableNotFound(name: Self.toolName)
    }

    let streams = ProcessStreams.inMemory
      .map(input: source.data(using: .utf8))
      .memorizedError()

    let result = try await Process.runAndCapture(
      executableURL,
      at: baseURL.deletingLastPathComponent(),
      streams: streams)

    if result.terminationStatus != 0 {
      throw RendererError.nonZeroExit(
        code: result.terminationStatus,
        stderr: result.error)
    }
    return result.output
  }
}
