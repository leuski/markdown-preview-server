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

  /// All known renderers, in display order, each marked available or not.
  private(set) var rendererEntries: [RendererEntry] = []

  /// Persisted identifier of the user's chosen renderer. May not match
  /// any currently-available renderer until discovery completes.
  var selectedRendererID: String? {
    didSet {
      UserDefaults.standard.set(selectedRendererID, forKey: Keys.rendererID)
      updateCurrentRenderer()
    }
  }

  var launchAtLogin: Bool {
    didSet {
      let applied = LoginItem.setEnabled(launchAtLogin)
      if applied != launchAtLogin {
        launchAtLogin = applied
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

  static let defaultPort: UInt16 = 8089

  init() {
    let storedPort = UserDefaults.standard.object(forKey: Keys.port) as? Int
    self.port = storedPort.flatMap { UInt16(exactly: $0) } ?? Self.defaultPort
    self.selectedRendererID = UserDefaults.standard.string(forKey: Keys.rendererID)
    self.launchAtLogin = LoginItem.isEnabled

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

  /// The entry actually used for rendering: the user's preferred entry if
  /// it is currently available, otherwise the first available entry.
  /// `nil` only when no renderer at all is available.
  var activeEntry: RendererEntry? {
    if let id = selectedRendererID,
       let entry = rendererEntries.first(where: { $0.id == id && $0.isAvailable })
    {
      return entry
    }
    return rendererEntries.first { $0.isAvailable }
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

  private func restartServerIfRunning() {
    if case .running = server.state {
      server.start(port: port)
    }
  }
}
