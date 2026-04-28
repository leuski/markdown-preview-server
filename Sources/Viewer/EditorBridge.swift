import AppKit
import Foundation
import WebKit
import os

/// Receives `{ "line": <Int> }` messages from the rendered preview and
/// opens the current document in BBEdit at that line. The bridge has no
/// own knowledge of the file path — it reads it from `documentURL`,
/// which the owning ViewerModel keeps current.
@MainActor
final class EditorBridge: NSObject, WKScriptMessageHandler {
  /// Name of the JavaScript message handler. JS calls
  /// `window.webkit.messageHandlers.editor.postMessage({ line: N })`.
  static let messageName = "editor"

  /// Snippet injected at document end. Cmd-click on any element with a
  /// `data-source-line` ancestor posts the line number back to Swift.
  static let userScript: String = """
    document.addEventListener('click', (event) => {
      if (!event.metaKey) return;
      const target = event.target.closest('[data-source-line]');
      if (!target) return;
      const line = parseInt(target.dataset.sourceLine, 10);
      if (Number.isNaN(line)) return;
      window.webkit.messageHandlers.\(messageName).postMessage({ line });
      event.preventDefault();
      event.stopPropagation();
    }, true);
    """

  var documentURL: URL?

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.leuski.Markdown-Eye",
    category: "EditorBridge")

  func userContentController(
    _ controller: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard let body = message.body as? [String: Any],
          let line = body["line"] as? Int
    else {
      logger.warning(
        "Ignoring malformed editor message: \(String(describing: message.body))")
      return
    }
    guard let documentURL else {
      logger.warning("Editor click ignored: no document URL bound")
      return
    }
    openInBBEdit(url: documentURL, line: line)
  }

  private func openInBBEdit(url: URL, line: Int) {
    // BBEdit registers x-bbedit:// (its own scheme) and txmt:// (the
    // TextMate-compatible cross-editor scheme). bbedit:// (no x-) is
    // NOT registered. Try x-bbedit first; fall back to txmt.
    let schemes = ["x-bbedit", "txmt"]
    for scheme in schemes {
      var components = URLComponents()
      components.scheme = scheme
      components.host = "open"
      components.queryItems = [
        URLQueryItem(name: "url", value: url.absoluteString),
        URLQueryItem(name: "line", value: String(line))
      ]
      guard let editorURL = components.url else { continue }
      if NSWorkspace.shared.open(editorURL) {
        return
      }
      logger.debug(
        "\(scheme, privacy: .public):// open failed, trying next scheme")
    }
    logger.error("""
      No editor handled the open URL for \(url.path, privacy: .public) \
      at line \(line). Tried: \
      \(schemes.joined(separator: ", "), privacy: .public)
      """)
  }
}
