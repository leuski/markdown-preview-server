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

  /// Set by the owning ViewerModel; receives the line clicked.
  /// Routing the actual open call through the model lets it consult
  /// the user's `EditorChoice` from `ViewerSettings`.
  var onEditorClick: ((Int) -> Void)?

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
      logger.warning("""
        Ignoring malformed editor message: \
        \(String(describing: message.body), privacy: .public)
        """)
      return
    }
    onEditorClick?(line)
  }
}
