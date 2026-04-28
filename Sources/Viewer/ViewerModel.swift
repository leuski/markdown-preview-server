import Foundation
import GalleyCoreKit
import Observation
import os
import SwiftUI
import WebKit

/// Per-document state for the native viewer. Owns the WebPage, the
/// rendering pipeline, the file watcher, and the editor bridge.
///
/// In-window navigation is browser-style: clicking a markdown link
/// rebinds this same model. A back/forward stack tracks the visited
/// URLs; toolbar buttons drive `goBack`, `goForward`, and `reload`.
@Observable
@MainActor
final class ViewerModel {
  let page: WebPage

  @ObservationIgnored let renderer: any MarkdownRenderer
  @ObservationIgnored let template: any Template
  @ObservationIgnored private let watcher = DocumentWatcher()
  @ObservationIgnored private let bridge = EditorBridge()
  @ObservationIgnored private let linkBridge = LinkBridge()

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
    let configuration = WebPage.Configuration()
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
    self.page = WebPage(configuration: configuration)
    self.renderer = SwiftMarkdownRenderer(annotatesSourceLines: true)
    self.template = BuiltInTemplate.shared

    // Browser-style navigation: clicking a markdown link in the
    // rendered preview pushes onto our history and rebinds this same
    // model rather than opening a new document window.
    linkBridge.onMarkdownLink = { [weak self] url in
      guard let self else { return }
      Task { await self.navigate(to: url) }
    }
  }

  // MARK: - Public entry points

  /// Initial bind (called from ContentView's `.task(id: fileURL)`).
  /// Resets history; this URL becomes the only entry on the stack.
  func bind(to url: URL) async {
    history = [url]
    currentIndex = 0
    await rebindCurrent()
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
    logger.notice("Binding to document: \(url.path, privacy: .public)")
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
    do {
      let source = try String(contentsOf: url, encoding: .utf8)
      let body = try await renderer.render(source, baseURL: url)
      let templateHTML = try template.loadHTML()
      let directory = url.deletingLastPathComponent()
      let context = PlaceholderContext(
        documentContent: body,
        documentURL: url,
        origin: directory)
      let html = context.substitute(into: templateHTML)
      // about:blank sidesteps the sandbox file:// baseURL trouble; the
      // rendered body itself doesn't depend on the base. Asset URL
      // resolution for images will be revisited with a URLSchemeHandler.
      let blank = URL(string: "about:blank")!
      logger.debug("Loading rendered HTML (\(html.count) bytes)")
      do {
        for try await _ in page.load(html: html, baseURL: blank) {}
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
