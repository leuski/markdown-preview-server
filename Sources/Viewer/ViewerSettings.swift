import Foundation
import GalleyCoreKit
import Observation
import SwiftUI

/// App-wide rendering preferences for the Viewer. Renderer selection
/// (catalog discovery + persisted ID) and the user's template store
/// both live here, separately from any single window's `ViewerModel`.
/// Windows read the active renderer + template at render time, so the
/// user can switch globally and have every open document re-render.
@Observable
@MainActor
final class ViewerSettings {
  /// All known renderers, in display order, each marked available or
  /// not. Populated asynchronously after init.
  private(set) var rendererEntries: [RendererEntry] = []

  /// Persisted identifier of the user's preferred renderer. May not
  /// match an available entry until discovery completes; we keep it
  /// even when unavailable so reinstalling the tool restores the
  /// selection.
  var selectedRendererID: String? {
    didSet {
      UserDefaults.standard.set(
        selectedRendererID, forKey: Keys.rendererID)
    }
  }

  @ObservationIgnored let templateStore: TemplateStore

  /// User's chosen editor target. Drives both cmd-click → editor and
  /// File > Open in Editor. Persisted as JSON so the full enum
  /// (preset / custom URL / app bundle) round-trips through
  /// UserDefaults in a single key.
  var editorChoice: EditorChoice {
    didSet { persistEditorChoice() }
  }

  private enum Keys {
    static let rendererID = "MarkdownEye.rendererID"
    static let editorChoice = "MarkdownEye.editorChoice"
  }

  init() {
    self.templateStore = TemplateStore()
    self.selectedRendererID = UserDefaults.standard.string(
      forKey: Keys.rendererID)
    self.editorChoice = Self.loadEditorChoice()
    Task { @MainActor in await self.discover() }
  }

  /// User's preferred entry if available, otherwise the first
  /// available entry. `nil` only when nothing is available.
  var activeEntry: RendererEntry? {
    if let id = selectedRendererID,
       let entry = rendererEntries.first(
         where: { $0.id == id && $0.isAvailable })
    {
      return entry
    }
    return rendererEntries.first { $0.isAvailable }
  }

  /// Renderer to use for the current preview. Wraps swift-markdown
  /// with `annotatesSourceLines: true` so cmd-click → BBEdit works.
  var activeRenderer: any MarkdownRenderer {
    let base = activeEntry?.renderer
      ?? SwiftMarkdownRenderer(annotatesSourceLines: true)
    if base.id == "swift-markdown" {
      return SwiftMarkdownRenderer(annotatesSourceLines: true)
    }
    return base
  }

  var activeTemplate: any Template {
    templateStore.selected
  }

  /// Non-nil when the user's preferred renderer exists in the catalog
  /// but its underlying tool is not installed.
  var preferredButUnavailableEntry: RendererEntry? {
    guard let id = selectedRendererID,
          let entry = rendererEntries.first(where: { $0.id == id }),
          !entry.isAvailable
    else { return nil }
    return entry
  }

  func selectRenderer(id: String) {
    selectedRendererID = id
  }

  func selectTemplate(_ template: any Template) {
    templateStore.select(template)
  }

  func rediscoverRenderers() async {
    await discover()
  }

  /// Two-way binding the menu's `Toggle` rows can drive.
  func rendererBinding(_ entry: RendererEntry) -> Binding<Bool> {
    Binding(
      get: { entry.id == self.activeEntry?.id },
      set: { isOn in if isOn { self.selectRenderer(id: entry.id) } }
    )
  }

  func templateBinding(_ template: any Template) -> Binding<Bool> {
    Binding(
      get: { template.id == self.templateStore.selectedID },
      set: { isOn in if isOn { self.selectTemplate(template) } }
    )
  }

  private static func loadEditorChoice() -> EditorChoice {
    guard let data = UserDefaults.standard.data(
      forKey: Keys.editorChoice),
      let decoded = try? JSONDecoder().decode(
        EditorChoice.self, from: data)
    else { return .default }
    return decoded
  }

  private func persistEditorChoice() {
    guard let data = try? JSONEncoder().encode(editorChoice)
    else { return }
    UserDefaults.standard.set(data, forKey: Keys.editorChoice)
  }

  private func discover() async {
    let entries = await MarkdownRendererCatalog.discoverAll()
    self.rendererEntries = entries
    if selectedRendererID == nil,
       let first = entries.first(where: { $0.isAvailable })?.id
    {
      selectedRendererID = first
    }
  }
}
