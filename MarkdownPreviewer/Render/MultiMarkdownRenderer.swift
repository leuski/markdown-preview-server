import Foundation
import ALFoundation

struct MultiMarkdownRenderer: MarkdownRenderer {
  let executableURL: URL
  let extraArguments: [String]

  init(executableURL: URL, extraArguments: [String] = []) {
    self.executableURL = executableURL
    self.extraArguments = extraArguments
  }

  func render(_ source: String, baseURL: URL) async throws -> String {
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
      throw RendererError.executableNotFound(executableURL.path)
    }

    let streams = ProcessStreams.inMemory
      .map(input: source.data(using: .utf8))
      .memorizedError()

    let arguments: [ProcessArgument] = extraArguments.map { $0 as ProcessArgument }

    let result = try await Process.runAndCapture(
      executableURL,
      with: arguments,
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
