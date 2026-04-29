import Foundation
import SwiftUI
import Observation
import GalleyCoreKit
import GalleyServerKit

@Observable
@MainActor
final class AppModel {
  var port: UInt16 {
    get {
      access(keyPath: \.port)
      let stored = UserDefaults.standard.object(forKey: Keys.port) as? Int
      return stored.flatMap { UInt16(exactly: $0) } ?? Self.defaultPort
    }
    set {
      withMutation(keyPath: \.port) {
        UserDefaults.standard.set(Int(newValue), forKey: Keys.port)
      }
      restartServerIfRunning()
    }
  }

  var launchAtLogin: Bool {
    get {
      access(keyPath: \.launchAtLogin)
      return LoginItem.isEnabled
    }
    set {
      withMutation(keyPath: \.launchAtLogin) {
        _ = LoginItem.setEnabled(newValue)
      }
    }
  }

  @ObservationIgnored let templateStore: TemplateStore
  @ObservationIgnored let templateChoice: TemplateChoice
  @ObservationIgnored let processorStore: ProcessorStore
  @ObservationIgnored let processorChoice: ProcessorChoice
  @ObservationIgnored lazy var server: PreviewServerController = {
    PreviewServerController(
      templateStore: self.templateStore,
      selectedTemplateProvider: { [weak self] in
        await self?.templateChoice.selected.template ?? .default
      },
      rendererProvider: { [weak self] in
        await self?.processorChoice.active.processor.renderer
      })
  }()

  private enum Keys {
    static let port = "MarkdownPreviewer.port"
    static let rendererID = "MarkdownPreviewer.rendererID"
    static let templateID = "MarkdownPreviewer.selectedTemplateID"
  }

  nonisolated static let defaultPort: UInt16 = 8089
  nonisolated static let defaultHost: String = "127.0.0.1"

  init() {
    let store = TemplateStore()
    self.templateStore = store
    self.templateChoice = TemplateChoice(store: store, key: Keys.templateID)
    let processorStore = ProcessorStore()
    self.processorStore = processorStore
    self.processorChoice = ProcessorChoice(
      store: processorStore, key: Keys.rendererID)

    startServer()

    Task { @MainActor in
      await self.rediscoverRenderers()
    }
  }

  nonisolated private static func hostURL(port: UInt16? = nil) -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = Self.defaultHost
    components.port = Int(port ?? Self.defaultPort)
    guard let url = components.url else {
      preconditionFailure("hostURL components produced no URL")
    }
    return url
  }

  var hostURL: URL {
    Self.hostURL(port: self.port)
  }

  /// Non-nil when the user's preferred renderer exists in the catalog
  /// but its underlying tool is not installed — UI surfaces this so the
  /// fallback isn't silent.
  var preferredButUnavailableProcessor: Processor? {
    processorChoice.preferredButUnavailable?.processor
  }

  /// Re-runs discovery (e.g. after the user installs a new tool).
  func rediscoverRenderers() async {
    await processorStore.discover()
  }

  private func startServer() {
    server.start(url: hostURL)
  }

  private func restartServerIfRunning() {
    if case .running = server.state {
      startServer()
    }
  }
}
