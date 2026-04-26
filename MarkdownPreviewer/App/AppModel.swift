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

  /// All renderers whose underlying tools were detected at launch.
  private(set) var availableRenderers: [any MarkdownRenderer] = []

  /// Persisted identifier of the user's chosen renderer. May not match
  /// any currently-available renderer until discovery completes.
  var selectedRendererID: String? {
    didSet {
      UserDefaults.standard.set(selectedRendererID, forKey: Keys.rendererID)
      updateCurrentRenderer()
    }
  }

  @ObservationIgnored let templateStore: TemplateStore
  @ObservationIgnored let server: PreviewServerController
  @ObservationIgnored private let currentRenderer = CurrentRenderer()

  private enum Keys {
    static let port = "MarkdownPreviewer.port"
    static let rendererID = "MarkdownPreviewer.rendererID"
  }

  static let defaultPort: UInt16 = 8089

  init() {
    let storedPort = UserDefaults.standard.object(forKey: Keys.port) as? Int
    self.port = storedPort.flatMap { UInt16(exactly: $0) } ?? Self.defaultPort
    self.selectedRendererID = UserDefaults.standard.string(forKey: Keys.rendererID)

    let store = TemplateStore()
    self.templateStore = store

    let box = currentRenderer
    let provider: @Sendable () -> (any MarkdownRenderer)? = { box.get() }
    self.server = PreviewServerController(
      templateStore: store,
      rendererProvider: provider)

    self.server.start(port: self.port)

    Task { @MainActor in
      await self.discoverRenderers()
    }
  }

  func selectRenderer(_ renderer: any MarkdownRenderer) {
    selectedRendererID = renderer.id
  }

  /// Re-runs discovery (e.g. after the user installs a new tool).
  func rediscoverRenderers() async {
    await discoverRenderers()
  }

  private func discoverRenderers() async {
    let renderers = await MarkdownRendererCatalog.discoverAll()
    self.availableRenderers = renderers
    if selectedRendererID == nil || !renderers.contains(where: { $0.id == selectedRendererID }) {
      selectedRendererID = renderers.first?.id
    } else {
      updateCurrentRenderer()
    }
  }

  private func updateCurrentRenderer() {
    let renderer = availableRenderers.first { $0.id == selectedRendererID }
    currentRenderer.set(renderer)
  }

  private func restartServerIfRunning() {
    if case .running = server.state {
      server.start(port: port)
    }
  }
}
