import Foundation
import GalleyCoreKit
import Observation
import SwiftUI

/// App-wide rendering preferences for the Viewer. Renderer selection
/// (catalog discovery + persisted ID) and the user's template store
/// both live here, separately from any single window's `DocumentModel`.
/// Windows read the active renderer + template at render time, so the
/// user can switch globally and have every open document re-render.
@Observable
@MainActor
final class AppModel {
  @ObservationIgnored let templateStore: TemplateStore
  @ObservationIgnored let templates: TemplateChoice
  @ObservationIgnored let processorStore: ProcessorStore
  @ObservationIgnored let processors: ProcessorChoice
  @ObservationIgnored let editors: EditorChoice

  /// When on, each window can pin its own renderer / template that
  /// wins over the global selection. Stored per-window via
  /// `@SceneStorage`; toggling this off doesn't erase the per-window
  /// values, but stops them from taking effect.
  var enablePerDocumentOverrides: Bool {
    didSet {
      UserDefaults.standard.set(
        enablePerDocumentOverrides, forKey: Keys.perDocOverrides)
    }
  }

  /// How the app should handle a new document open request from
  /// Finder, the open panel, or Open Recent. Defaults to opening a
  /// fresh window (the historical behavior).
  var openBehavior: OpenBehavior {
    didSet {
      UserDefaults.standard.set(
        openBehavior.rawValue, forKey: Keys.openBehavior)
    }
  }

  private enum Keys {
    static let rendererID = "MarkdownEye.rendererID"
    static let perDocOverrides = "MarkdownEye.perDocumentOverrides"
    static let openBehavior = "MarkdownEye.openBehavior"
    static let templateID = "MarkdownEye.selectedTemplateID"
  }

  init(skipDiscovery: Bool = false) {
    let store = TemplateStore()
    self.templateStore = store
    self.templates = TemplateChoice(store: store, key: Keys.templateID)
    let processorStore = ProcessorStore()
    self.processorStore = processorStore
    self.processors = ProcessorChoice(
      store: processorStore, key: Keys.rendererID)
    self.editors = EditorChoice()
    self.enablePerDocumentOverrides = UserDefaults.standard.bool(
      forKey: Keys.perDocOverrides)
    self.openBehavior = OpenBehavior(
      rawValue: UserDefaults.standard.string(forKey: Keys.openBehavior)
        ?? "")
      ?? .newWindow
    if !skipDiscovery {
      Task { @MainActor in await self.discover() }
    }
  }

  func template(forID id: String) -> Template? {
    templateStore.template(forID: id)
  }

  /// User's preferred processor if available, otherwise the first
  /// available entry; `nil` only when nothing is available.
  var activeProcessor: Processor? {
    let value = processors.active.value
    return value.isAvailable ? value : nil
  }

  /// Renderer to use for the current preview. Wraps swift-markdown
  /// with `annotatesSourceLines: true` so cmd-click → BBEdit works.
  var activeRenderer: any MarkdownRenderer {
    activeProcessor?.renderer ?? SwiftMarkdownRenderer()
  }

  var activeTemplate: Template {
    templates.selected.value
  }

  /// Non-nil when the user's preferred renderer exists in the catalog
  /// but its underlying tool is not installed.
  var preferredButUnavailableProcessor: Processor? {
    processors.preferredButUnavailable?.value
  }

  func selectTemplate(_ template: Template) {
    templates.selected = TemplateChoice.Value(template)
  }

  func rediscoverRenderers() async {
    await processorStore.discover()
  }

  private func discover() async {
    await processorStore.discover()
  }

  func revealTemplatesFolder() {
    templateStore.revealFolder()
  }
}

/// Strategy for handling an "open this file" request from Finder, the
/// open panel, or Open Recent when at least one Viewer window is
/// already up. With no existing windows, every behavior collapses to
/// "open a new window."
enum OpenBehavior: String, CaseIterable, Identifiable, Sendable {
  /// Always spawn a fresh window.
  case newWindow
  /// Spawn a fresh window and merge it as a tab into the frontmost
  /// existing window (so the user ends up with a tab strip).
  case newTab
  /// Reuse the frontmost window — rebind it to the new document
  /// instead of creating another window.
  case replaceCurrent

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .newWindow: return "New Window"
    case .newTab: return "New Tab in Frontmost Window"
    case .replaceCurrent: return "Replace Frontmost Document"
    }
  }
}
