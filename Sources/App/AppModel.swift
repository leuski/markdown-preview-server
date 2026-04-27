import Foundation
import SwiftUI
import Observation

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

  /// All known renderers, in display order, each marked available or not.
  private(set) var rendererEntries: [RendererEntry] = []

  /// Persisted identifier of the user's chosen renderer. May not match
  /// any currently-available renderer until discovery completes.
  var selectedRendererID: String? {
    get {
      access(keyPath: \.selectedRendererID)
      return UserDefaults.standard.string(forKey: Keys.rendererID)
    }
    set {
      withMutation(keyPath: \.selectedRendererID) {
        UserDefaults.standard.set(newValue, forKey: Keys.rendererID)
      }
      updateCurrentRenderer()
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
  @ObservationIgnored let server: PreviewServerController
  @ObservationIgnored private let currentRenderer = CurrentRenderer()

  private enum Keys {
    static let port = "MarkdownPreviewer.port"
    static let rendererID = "MarkdownPreviewer.rendererID"
  }

  nonisolated static let defaultPort: UInt16 = 8089
  nonisolated static let defaultHost: String = "127.0.0.1"

  init() {
    let store = TemplateStore()
    self.templateStore = store

    let box = currentRenderer
    let provider: @Sendable () -> (any MarkdownRenderer)? = { box.get() }
    self.server = PreviewServerController(
      templateStore: store,
      rendererProvider: provider)

    startServer()

    Task { @MainActor in
      await self.discoverRenderers()
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

  func selectedEntryBinding(_ entry: RendererEntry) -> Binding<Bool> {
    Binding(
      get: { entry.id == self.activeEntry?.id },
      set: { _ in self.selectedRendererID = entry.id }
    )
  }

  var selectedEntry: RendererEntry? {
    selectedRendererID.flatMap { id in
      rendererEntries.first { $0.id == id && $0.isAvailable }
    }
  }

  /// The entry actually used for rendering: the user's preferred entry if
  /// it is currently available, otherwise the first available entry.
  /// `nil` only when no renderer at all is available.
  var activeEntry: RendererEntry? {
    selectedEntry ?? rendererEntries.first { $0.isAvailable }
  }

  /// Non-nil when the user's preferred renderer exists in the catalog
  /// but its underlying tool is not installed — UI surfaces this so the
  /// fallback isn't silent.
  var preferredButUnavailableEntry: RendererEntry? {
    guard let id = selectedRendererID,
          let entry = rendererEntries.first(where: { $0.id == id }),
          !entry.isAvailable
    else { return nil }
    return entry
  }

  /// Re-runs discovery (e.g. after the user installs a new tool).
  func rediscoverRenderers() async {
    await discoverRenderers()
  }

  private func discoverRenderers() async {
    let entries = await MarkdownRendererCatalog.discoverAll()
    self.rendererEntries = entries
    // First launch only: pick a default. Otherwise keep the user's
    // preference even if it is currently unavailable, so reinstalling
    // the tool brings the selection back without further input.
    if selectedRendererID == nil {
      selectedRendererID = entries.first { $0.isAvailable }?.id
    } else {
      updateCurrentRenderer()
    }
  }

  private func updateCurrentRenderer() {
    currentRenderer.set(activeEntry?.renderer)
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
