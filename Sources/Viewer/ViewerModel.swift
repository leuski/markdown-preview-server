import Foundation
import GalleyCoreKit
import Observation
import os
import SwiftUI
import WebKit

/// Per-document state for the native viewer. Owns the WebPage, the
/// file watcher, and the editor bridge. Renderer and template come
/// from the shared `ViewerSettings` so global selection changes
/// re-render every open window.
///
/// In-window navigation is browser-style: clicking a markdown link
/// rebinds this same model. A back/forward stack tracks the visited
/// URLs; toolbar buttons drive `goBack`, `goForward`, and `reload`.
@Observable
@MainActor
final class ViewerModel {
  let page: WebPage

  @ObservationIgnored private let watcher = DocumentWatcher()
  @ObservationIgnored private let bridge = EditorBridge()
  @ObservationIgnored private let linkBridge = LinkBridge()
  @ObservationIgnored private weak var settings: ViewerSettings?
  @ObservationIgnored private let templateBox: TemplateBox

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
    category: "ViewerModel")

  init() {
    var configuration = WebPage.Configuration()
    let controller = configuration.userContentController
    controller.add(bridge, name: EditorBridge.messageName)
    controller.add(linkBridge, name: LinkBridge.messageName)
    controller.addUserScript(WKUserScript(
      source: EditorBridge.userScript,
      injectionTime: .atDocumentEnd,
      forMainFrameOnly: true))
    controller.addUserScript(WKUserScript(
      source: LinkBridge.userScript,
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
  }

  // MARK: - Public entry points

  /// Inject the shared rendering settings. Called by ContentView
  /// before the first bind; safe to call again.
  func bindSettings(_ settings: ViewerSettings) {
    self.settings = settings
    templateBox.template = settings.activeTemplate
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
  func navigate(to url: URL) async {
    if currentIndex >= 0, currentIndex < history.count {
      history.removeSubrange((currentIndex + 1)..<history.count)
    }
    history.append(url)
    currentIndex = history.count - 1
    await rebindCurrent()
  }

  func goBack() async {
    guard canGoBack else { return }
    currentIndex -= 1
    await rebindCurrent()
  }

  func goForward() async {
    guard canGoForward else { return }
    currentIndex += 1
    await rebindCurrent()
  }

  func reload() async {
    await renderCurrent()
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

    await renderCurrent()

    let stream = await watcher.subscribe(to: url)
    for await _ in stream {
      if Task.isCancelled || bindGeneration != myGeneration { break }
      await renderCurrent()
    }
  }

  private func renderCurrent() async {
    guard let url = documentURL else {
      logger.warning("renderCurrent() called with no documentURL")
      return
    }
    let renderer = settings?.activeRenderer
      ?? SwiftMarkdownRenderer(annotatesSourceLines: true)
    let template = settings?.activeTemplate ?? BuiltInTemplate.shared
    // Keep the scheme handler's template pointer current — the user
    // may have switched templates since the last bind.
    templateBox.template = template
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
}

/// Reference holder so the URL scheme handler — which captures the
/// box at WebPage creation time, before settings are injected —
/// always sees the latest template. ViewerModel updates `template`
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

