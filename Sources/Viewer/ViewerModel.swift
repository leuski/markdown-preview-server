import Foundation
import GalleyCoreKit
import Observation
import os
import SwiftUI
import WebKit

/// Per-document state for the native viewer. Owns the WebPage, the
/// rendering pipeline, the file watcher, and the editor bridge.
@Observable
@MainActor
final class ViewerModel {
  let page: WebPage

  @ObservationIgnored let renderer: any MarkdownRenderer
  @ObservationIgnored let template: any Template
  @ObservationIgnored private let watcher = DocumentWatcher()
  @ObservationIgnored private let bridge = EditorBridge()

  private(set) var documentURL: URL?
  private(set) var lastError: String?

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.leuski.Markdown-Eye",
    category: "ViewerModel")

  init() {
    let configuration = WebPage.Configuration()
    configuration.userContentController.add(
      bridge, name: EditorBridge.messageName)
    configuration.userContentController.addUserScript(WKUserScript(
      source: EditorBridge.userScript,
      injectionTime: .atDocumentEnd,
      forMainFrameOnly: true))
    self.page = WebPage(configuration: configuration)
    self.renderer = SwiftMarkdownRenderer(annotatesSourceLines: true)
    self.template = BuiltInTemplate.shared
  }

  /// Bind the model to a document URL. Drives the initial render and
  /// keeps reloading on file changes for as long as the calling Task
  /// stays alive (cooperative cancellation).
  func bind(to url: URL) async {
    logger.notice("Binding to document: \(url.path, privacy: .public)")
    documentURL = url
    bridge.documentURL = url
    await reload()
    let stream = await watcher.subscribe(to: url)
    for await _ in stream {
      if Task.isCancelled { break }
      await reload()
    }
  }

  private func reload() async {
    guard let url = documentURL else {
      logger.warning("reload() called with no documentURL")
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
        reload failed: \(error.localizedDescription, privacy: .public)
        """)
      lastError = error.localizedDescription
    }
  }

}
