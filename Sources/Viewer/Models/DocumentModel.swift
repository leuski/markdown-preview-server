import AppKit
import Foundation
import GalleyCoreKit
import Observation
import os
import SwiftUI
import WebKit

/// Per-document state for the native viewer. Owns the WebPage, the
/// file watcher, and the editor bridge. Renderer and template come
/// from the shared `AppModel` so global selection changes
/// re-render every open window.
///
/// In-window navigation is browser-style: clicking a markdown link
/// rebinds this same model. A back/forward stack tracks the visited
/// URLs; toolbar buttons drive `goBack`, `goForward`, and `reload`.
@Observable
@MainActor
final class DocumentModel {
  let page: WebPage

  @ObservationIgnored private let watcher = DocumentWatcher()
  @ObservationIgnored private let bridge = EditorBridge()
  @ObservationIgnored private let linkBridge = LinkBridge()
  @ObservationIgnored private weak var settings: AppModel?
  @ObservationIgnored private let templateBox: TemplateBox

  /// Per-window template / processor choices. Each struct holds a
  /// `Binding<String?>` to a `@SceneStorage` slot owned by the view,
  /// so reading/writing `selected` is the same as reading/writing
  /// the persisted scene state. `nil` until
  /// `bindSettings(_:templates:processors:)` runs.
  @ObservationIgnored private var templates: SceneTemplateChoice?
  @ObservationIgnored private var processors: SceneProcessorChoice?

  private(set) var documentURL: URL?
  private(set) var lastError: String?

  /// Visited documents in chronological order; `currentIndex` points
  /// at the one currently rendered. Navigation actions move
  /// `currentIndex` and rebind without truncating the stack — so
  /// pressing Forward after Back works.
  private var history: [URL] = []
  private var currentIndex: Int = -1

  var canGoBack: Bool { currentIndex > 0 }
  var canGoForward: Bool { currentIndex >= 0 && currentIndex < history.count - 1 }

  /// Increments on every `bind(to:)` call. Watcher loops captured by
  /// older bind invocations check this and bail out when superseded.
  @ObservationIgnored private var bindGeneration: Int = 0

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.leuski.Markdown-Eye",
    category: "DocumentModel")

  init() {
    var configuration = WebPage.Configuration()
    let controller = configuration.userContentController
    controller.add(bridge, name: EditorBridge.messageName)
    controller.add(linkBridge, name: LinkBridge.messageName)
    // One script handles both cmd-click → editor and plain click →
    // in-window nav, so we don't depend on capture-phase ordering
    // between two listeners — which appears to drop the editor
    // listener after the first navigation in macOS 26 WebPage.
    controller.addUserScript(WKUserScript(
      source: EditorBridge.userScript,
      injectionTime: .atDocumentEnd,
      forMainFrameOnly: true))

    // Custom URL scheme so template-bundled assets (CSS, fonts,
    // images) resolve from disk through the SwiftUI WebView. Reads
    // the active template at request time via `templateBox`, which
    // is populated by `bindSettings(_:)`.
    let box = TemplateBox()
    self.templateBox = box
    let handler = PreviewSchemeHandler(
      templateProvider: { box.template ?? BuiltInTemplate.shared })
    configuration.urlSchemeHandlers[PreviewSchemeHandler.scheme] = handler

    self.page = WebPage(configuration: configuration)

    // Browser-style navigation: clicking a markdown link in the
    // rendered preview pushes onto our history and rebinds this same
    // model rather than opening a new document window.
    linkBridge.onMarkdownLink = { [weak self] url in
      guard let self else { return }
      Task { await self.navigate(to: url) }
    }

    // Cmd-click in the preview: route through the model so we read
    // the current `EditorChoice` from settings on every click.
    bridge.onEditorClick = { [weak self] line in
      guard let self else { return }
      Task { await self.openInEditor(line: line) }
    }
  }

  /// Open the current document in the user's chosen editor.
  /// `line` is non-nil for cmd-click on a `data-source-line` block;
  /// nil for File > Open in Editor (jump to top).
  func openInEditor(line: Int? = nil) async {
    guard let url = documentURL else {
      logger.warning("openInEditor ignored: no document URL bound")
      return
    }
    let value = settings?.editors.selected ?? .default
    await openFileInEditor(
      value, fileURL: url, line: line, logger: logger)
  }

  // MARK: - Public entry points

  /// Inject the shared rendering settings and the per-window template
  /// / processor choices. Called by ContentView before the first bind;
  /// safe to call again. Both choice structs read/write the view's
  /// `@SceneStorage`-backed override slots, so the model and the
  /// override menus agree by construction.
  func bindSettings(
    _ settings: AppModel,
    templates: SceneTemplateChoice,
    processors: SceneProcessorChoice
  ) {
    self.settings = settings
    self.templates = templates
    self.processors = processors
    templateBox.template = resolvedTemplate()
  }

  /// Initial bind (called from ContentView's `.task(id: fileURL)`).
  /// Resets history; this URL becomes the only entry on the stack.
  func bind(to url: URL) async {
    history = [url]
    currentIndex = 0
    await rebindCurrent()
  }

  /// Restore a previously-saved history stack. Used at window
  /// re-open time to pick up where the user left off — the active
  /// document and the back/forward stack are both re-established.
  func restore(snapshot: HistorySnapshot) async {
    guard !snapshot.urls.isEmpty,
          snapshot.currentIndex >= 0,
          snapshot.currentIndex < snapshot.urls.count
    else { return }
    history = snapshot.urls
    currentIndex = snapshot.currentIndex
    await rebindCurrent()
  }

  /// Codable view of the back/forward stack for `@SceneStorage`.
  /// Returns nil when there is nothing meaningful to persist.
  var historySnapshot: HistorySnapshot? {
    guard !history.isEmpty,
          currentIndex >= 0,
          currentIndex < history.count
    else { return nil }
    return HistorySnapshot(urls: history, currentIndex: currentIndex)
  }

  /// Push a new URL onto the history and navigate to it. Truncates
  /// any forward entries (browser-standard new-link behaviour).
  ///
  /// If the target file isn't readable, surfaces an error and leaves
  /// history, bridges, and the visible document untouched — that way
  /// a broken link click doesn't strand the window with a corrupted
  /// base URL the link bridge would resolve subsequent clicks against.
  func navigate(to url: URL) async {
    guard reportIfUnreachable(url) else { return }
    if currentIndex >= 0, currentIndex < history.count {
      history.removeSubrange((currentIndex + 1)..<history.count)
    }
    history.append(url)
    currentIndex = history.count - 1
    await rebindCurrent()
  }

  func goBack() async {
    guard canGoBack else { return }
    let target = history[currentIndex - 1]
    guard reportIfUnreachable(target) else { return }
    currentIndex -= 1
    await rebindCurrent()
  }

  func goForward() async {
    guard canGoForward else { return }
    let target = history[currentIndex + 1]
    guard reportIfUnreachable(target) else { return }
    currentIndex += 1
    await rebindCurrent()
  }

  /// Verify a link target is readable before we commit to navigating
  /// to it. Returns `true` when the file exists; otherwise sets
  /// `lastError` and returns `false`.
  private func reportIfUnreachable(_ url: URL) -> Bool {
    if FileManager.default.isReadableFile(atPath: url.path) {
      lastError = nil
      return true
    }
    lastError = "Cannot open \(url.lastPathComponent): file not found."
    NSSound.beep()
    return false
  }

  func reload() async {
    await renderCurrent(preserveScroll: true)
  }

  /// Rename the current document on disk and re-bind the watcher /
  /// bridges to the new path. History entries that point at the old
  /// URL are rewritten in place so Back/Forward stays correct.
  /// Returns the new URL on success; throws if the move fails (the
  /// caller is expected to revert the title binding in that case).
  @discardableResult
  func renameCurrentDocument(toName newName: String) async throws -> URL {
    guard let oldURL = documentURL else {
      throw CocoaError(.fileNoSuchFile)
    }
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          !trimmed.contains("/"),
          trimmed != oldURL.lastPathComponent
    else { return oldURL }

    let newURL = oldURL.deletingLastPathComponent()
      .appendingPathComponent(trimmed)
    do {
      try FileManager.default.moveItem(at: oldURL, to: newURL)
    } catch {
      lastError = "Rename failed: \(error.localizedDescription)"
      throw error
    }
    lastError = nil

    // Patch every history entry that referenced the old URL — Back
    // would otherwise lead to a now-missing path and trip the
    // unreachable-link guard.
    history = history.map { $0 == oldURL ? newURL : $0 }
    await rebindCurrent()
    return newURL
  }

  // MARK: - Internals

  /// Rebind the model to whichever URL is at `currentIndex`. Drives
  /// the initial render and keeps reloading on file changes until
  /// another rebind supersedes this one.
  private func rebindCurrent() async {
    guard currentIndex >= 0, currentIndex < history.count else { return }
    let url = history[currentIndex]

    bindGeneration &+= 1
    let myGeneration = bindGeneration
    logger.debug("Binding to document: \(url.path, privacy: .public)")
    documentURL = url
    bridge.documentURL = url
    linkBridge.documentURL = url

    await renderCurrent(preserveScroll: false)

    let stream = await watcher.subscribe(to: url)
    for await _ in stream {
      if Task.isCancelled || bindGeneration != myGeneration { break }
      // Keep the user's place when the file changes on disk —
      // re-rendering otherwise snaps the WebView back to the top.
      await renderCurrent(preserveScroll: true)
    }
  }

  private func renderCurrent(preserveScroll: Bool) async {
    guard let url = documentURL else {
      logger.warning("renderCurrent() called with no documentURL")
      return
    }
    let renderer = resolvedRenderer()
    let template = resolvedTemplate()
    // Keep the scheme handler's template pointer current — the user
    // may have switched templates since the last bind.
    templateBox.template = template

    // Snapshot scroll position *before* re-rendering so we can hand it
    // back to the page after load. Best-effort: a nil/throwing read
    // (e.g. very first render) just leaves us at the top.
    let savedScrollY: Double = preserveScroll
      ? await currentScrollY() ?? 0
      : 0

    do {
      let source = try String(contentsOf: url, encoding: .utf8)
      let body = try await renderer.render(source, baseURL: url)
      let templateHTML = try template.loadHTML()
      let origin = PreviewSchemeHandler.originURL
      let context = PlaceholderContext(
        documentContent: body,
        documentURL: url,
        origin: origin)
      let substituted = context.substitute(into: templateHTML)
      let html = template.rewriteAssets(in: substituted, origin: origin)
      logger.debug("Loading rendered HTML (\(html.count) bytes)")
      do {
        for try await _ in page.load(html: html, baseURL: origin) {}
        lastError = nil
        if savedScrollY > 0 {
          await restoreScrollY(savedScrollY)
        }
      } catch {
        logger.error("""
          Navigation failed: \(error.localizedDescription, privacy: .public)
          """)
        lastError = error.localizedDescription
      }
    } catch {
      logger.error("""
        render failed: \(error.localizedDescription, privacy: .public)
        """)
      lastError = error.localizedDescription
    }
  }

  /// Resolve the renderer for the next render. When the per-document
  /// override flag is on, the window-local choice wins (falling back
  /// to the global selection if its pick is unavailable). Otherwise
  /// always use the global selection.
  private func resolvedRenderer() -> any MarkdownRenderer {
    guard let processors else {
      return settings?.activeRenderer ?? SwiftMarkdownRenderer()
    }
    if settings?.enablePerDocumentOverrides == true {
      let pick = processors.selected.processor
      if let renderer = pick.renderer { return renderer }
      // Local pick is unavailable — fall back to the resolved global
      // (which itself falls back to the catalog's first-available
      // entry).
    }
    return processors.globalProcessor.processor.renderer
      ?? SwiftMarkdownRenderer()
  }

  private func resolvedTemplate() -> any Template {
    guard let templates else {
      return settings?.activeTemplate ?? BuiltInTemplate.shared
    }
    if settings?.enablePerDocumentOverrides == true {
      return templates.selected.template
    }
    // Per-document override is off: always use the global selection,
    // even if a window happens to have a stale local pick.
    return templates.globalTemplate
  }

  private func currentScrollY() async -> Double? {
    do {
      let value = try await page.callJavaScript("return window.scrollY;")
      if let number = value as? Double { return number }
      if let number = value as? NSNumber { return number.doubleValue }
      return nil
    } catch {
      return nil
    }
  }

  private func restoreScrollY(_ y: Double) async {
    let js = "window.scrollTo(0, \(y));"
    _ = try? await page.callJavaScript(js)
  }
}

/// Reference holder so the URL scheme handler — which captures the
/// box at WebPage creation time, before settings are injected —
/// always sees the latest template. DocumentModel updates `template`
/// in `bindSettings(_:)` and at the start of every render.
@MainActor
final class TemplateBox {
  var template: (any Template)?
}

/// Serializable form of a window's back/forward stack. Persisted via
/// `@SceneStorage` so each window restores to whichever document the
/// user was viewing when the app last quit.
struct HistorySnapshot: Codable, Sendable, Equatable {
  let urls: [URL]
  let currentIndex: Int
}
