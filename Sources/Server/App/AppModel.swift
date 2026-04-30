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
  let templates: TemplateChoice
  @ObservationIgnored let processorStore: ProcessorStore
  let processors: ProcessorChoice
  @ObservationIgnored lazy var server: PreviewServerController = {
    PreviewServerController(
      templateStore: self.templateStore,
      selectedTemplateProvider: { [weak self] in
        await self?.templates.selected.value ?? .default
      },
      rendererProvider: { [weak self] in
        await self?.processors.selected.value.renderer
      })
  }()

  /// The display name of a previously-picked processor that is no
  /// longer available. Set by `reconcile()` after discovery; cleared
  /// when the user dismisses the notice or makes a new selection.
  var displacedProcessorName: String?

  /// The display name of a previously-picked template whose folder is
  /// no longer present.
  var displacedTemplateName: String?

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
    self.templates = TemplateChoice(store: store, key: Keys.templateID)
    let processorStore = ProcessorStore()
    self.processorStore = processorStore
    self.processors = ProcessorChoice(
      store: processorStore, key: Keys.rendererID)

    // Initial template reconcile (TemplateStore.reload() ran during
    // its own init, before onReload was set).
    self.displacedTemplateName = self.templates.reconcile()
    store.onReload = { [weak self] in self?.afterTemplateReload() }

    startServer()

    Task { @MainActor in
      await self.rediscoverRenderers()
    }
  }

  private func afterTemplateReload() {
    if let displaced = templates.reconcile() {
      displacedTemplateName = displaced
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

  /// Re-runs discovery (e.g. after the user installs a new tool) and
  /// reconciles the persisted pick against the fresh catalog.
  func rediscoverRenderers() async {
    await processorStore.discover()
    if let displaced = processors.reconcile() {
      displacedProcessorName = displaced
    }
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
