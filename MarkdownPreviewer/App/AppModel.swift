import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
final class AppModel {
  var port: UInt16 {
    didSet {
      UserDefaults.standard.set(Int(port), forKey: Keys.port)
      restartServerIfRunning()
    }
  }
  var rendererPath: String {
    didSet {
      UserDefaults.standard.set(rendererPath, forKey: Keys.rendererPath)
      rendererSettings.update(path: rendererPath, args: rendererArgs)
    }
  }
  var rendererArgs: String {
    didSet {
      UserDefaults.standard.set(rendererArgs, forKey: Keys.rendererArgs)
      rendererSettings.update(path: rendererPath, args: rendererArgs)
    }
  }

  @ObservationIgnored let templateStore: TemplateStore
  @ObservationIgnored let server: PreviewServerController
  @ObservationIgnored private let rendererSettings: RendererSettings

  private enum Keys {
    static let port = "MarkdownPreviewer.port"
    static let rendererPath = "MarkdownPreviewer.rendererPath"
    static let rendererArgs = "MarkdownPreviewer.rendererArgs"
  }

  static let defaultPort: UInt16 = 8089
  static var defaultRendererPath: String {
    let candidates = [
      "/opt/homebrew/bin/multimarkdown",
      "/usr/local/bin/multimarkdown",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
      ?? "/usr/local/bin/multimarkdown"
  }

  init() {
    let storedPort = UserDefaults.standard.object(forKey: Keys.port) as? Int
    let initialPort = storedPort.flatMap { UInt16(exactly: $0) } ?? Self.defaultPort
    let initialPath = UserDefaults.standard.string(forKey: Keys.rendererPath)
      ?? Self.defaultRendererPath
    let initialArgs = UserDefaults.standard.string(forKey: Keys.rendererArgs) ?? ""

    self.port = initialPort
    self.rendererPath = initialPath
    self.rendererArgs = initialArgs

    let store = TemplateStore()
    self.templateStore = store

    let settings = RendererSettings()
    settings.update(path: initialPath, args: initialArgs)
    self.rendererSettings = settings

    let provider: @Sendable () -> any MarkdownRenderer = {
      let snapshot = settings.snapshot()
      return MultiMarkdownRenderer(
        executableURL: URL(fileURLWithPath: snapshot.path),
        extraArguments: snapshot.args
          .split(whereSeparator: { $0.isWhitespace })
          .map(String.init))
    }
    self.server = PreviewServerController(
      templateStore: store,
      rendererProvider: provider)

    self.server.start(port: initialPort)
  }

  func startServer() {
    server.start(port: port)
  }

  func restartServer() {
    server.start(port: port)
  }

  private func restartServerIfRunning() {
    if case .running = server.state {
      server.start(port: port)
    }
  }
}
