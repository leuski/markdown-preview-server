import Foundation
import GalleyCoreKit
import Observation
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
  @ObservationIgnored private var watchTask: Task<Void, Never>?

  private(set) var documentURL: URL?
  private(set) var lastError: String?

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

  func bind(to url: URL) {
    documentURL = url
    bridge.documentURL = url
    Task { await self.reload() }
    startWatching(url: url)
  }

  private func startWatching(url: URL) {
    watchTask?.cancel()
    let watcher = self.watcher
    watchTask = Task { [weak self] in
      let stream = await watcher.subscribe(to: url)
      for await _ in stream {
        guard let self else { break }
        await self.reload()
      }
    }
  }

  private func reload() async {
    guard let url = documentURL else { return }
    do {
      let source = try String(contentsOf: url, encoding: .utf8)
      let body = try await renderer.render(source, baseURL: url)
      let templateHTML = try template.loadHTML()
      let directory = url.deletingLastPathComponent()
      let origin = URL(fileURLWithPath: directory.path)
      let context = PlaceholderContext(
        documentContent: body,
        documentURL: url,
        origin: origin)
      let html = context.substitute(into: templateHTML)
      _ = page.load(html: html, baseURL: directory)
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  deinit {
    watchTask?.cancel()
  }
}
