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
  let templates: TemplateChoice
  @ObservationIgnored let processorStore: ProcessorStore
  let processors: ProcessorChoice
  @ObservationIgnored let editors: EditorChoice

  /// The display name of a previously-picked processor that is no
  /// longer available. Set by `reconcile()` after discovery; cleared
  /// when the user dismisses the notice or makes a new selection.
  var displacedProcessorName: String?

  /// The display name of a previously-picked template whose folder is
  /// no longer present.
  var displacedTemplateName: String?

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

    // Initial template reconcile (TemplateStore.reload() ran during
    // its own init, before onReload was set).
    self.displacedTemplateName = self.templates.reconcile()
    store.onReload = { [weak self] in self?.afterTemplateReload() }

    if !skipDiscovery {
      Task { @MainActor in await self.rediscoverRenderers() }
    }
  }

  func template(forID id: String) -> Template? {
    templateStore.existingTemplate(forID: id)
  }

  /// Renderer to use for the current preview. Wraps swift-markdown
  /// with `annotatesSourceLines: true` so cmd-click → BBEdit works.
  var activeRenderer: any MarkdownRenderer {
    processors.selected.value.renderer ?? SwiftMarkdownRenderer()
  }

  var activeTemplate: Template {
    templates.selected.value
  }

  func selectTemplate(_ template: Template) {
    templates.selected = TemplateChoice.Element(template)
  }

  func rediscoverRenderers() async {
    await processorStore.discover()
    if let displaced = processors.reconcile() {
      displacedProcessorName = displaced
    }
  }

  private func afterTemplateReload() {
    if let displaced = templates.reconcile() {
      displacedTemplateName = displaced
    }
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
