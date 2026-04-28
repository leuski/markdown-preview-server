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

  /// Single combined click handler for cmd-click → editor and plain
  /// click → in-window navigation. Routing both cases through one
  /// `addEventListener` removes ambiguity around capture-phase
  /// ordering between two scripts, and `stopImmediatePropagation`
  /// guarantees we don't fall through to a duplicate listener that
  /// could survive across navigations.
  static let userScript: String = """
    document.addEventListener('click', (event) => {
      if (event.metaKey) {
        const target = event.target.closest('[data-source-line]');
        if (target) {
          const line = parseInt(target.dataset.sourceLine, 10);
          if (!Number.isNaN(line)) {
            event.preventDefault();
            event.stopImmediatePropagation();
            window.webkit.messageHandlers.\(messageName).postMessage(
              { line });
            return;
          }
        }
        // Cmd-click missed a source-line target — still suppress any
        // default WebView action (e.g. open-in-new-window for links).
        event.preventDefault();
        event.stopImmediatePropagation();
        return;
      }
      const link = event.target.closest('a[href]');
      if (!link) return;
      const href = link.getAttribute('href');
      if (!href || href.startsWith('#')) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      window.webkit.messageHandlers.\(LinkBridge.messageName).postMessage(
        { href });
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
