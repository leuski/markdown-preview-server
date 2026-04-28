import AppKit
import Foundation
import GalleyCoreKit
import WebKit
import os

/// Handles plain-click on `<a href>` elements inside the rendered
/// preview: resolves relative paths against the current document, and
/// opens the target. Markdown files open as new Viewer documents
/// (which then participate in macOS native window tabbing); everything
/// else is handed off to LaunchServices.
@MainActor
final class LinkBridge: NSObject, WKScriptMessageHandler {
  /// JS message handler name. JS calls
  /// `window.webkit.messageHandlers.linkclick.postMessage({ href })`.
  static let messageName = "linkclick"

  /// User script. Plain (non-cmd) click on any `<a href>` posts the
  /// href back to Swift after preventing the default WebView nav.
  /// In-page anchors (`#…`) and anything cmd-clicked is left to the
  /// editor bridge.
  static let userScript: String = """
    document.addEventListener('click', (event) => {
      if (event.metaKey) return;
      const link = event.target.closest('a[href]');
      if (!link) return;
      const href = link.getAttribute('href');
      if (!href || href.startsWith('#')) return;
      event.preventDefault();
      event.stopPropagation();
      window.webkit.messageHandlers.\(messageName).postMessage({ href });
    }, true);
    """

  /// The document being previewed. Resolves relative hrefs.
  var documentURL: URL?

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.leuski.Markdown-Eye",
    category: "LinkBridge")

  func userContentController(
    _ controller: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard let body = message.body as? [String: Any],
          let href = body["href"] as? String
    else {
      logger.warning(
        "Ignoring malformed link message: \(String(describing: message.body))")
      return
    }
    handle(href: href)
  }

  private func handle(href: String) {
    guard let target = resolve(href: href) else {
      logger.warning("Could not resolve link href: \(href, privacy: .public)")
      return
    }
    logger.notice("Opening link: \(target.absoluteString, privacy: .public)")

    // NSWorkspace.open routes through LaunchServices, which picks the
    // right handler app for the URL. For .md files, that's us (we
    // registered the markdown UTI). For other URLs, it's the system
    // default. LaunchServices grants the destination app sandboxed
    // read access to the file as part of the launch, which is the
    // sandbox-friendly way to do cross-document navigation.
    let opened = NSWorkspace.shared.open(target)
    if !opened {
      logger.error("""
        NSWorkspace.open returned false for \
        \(target.absoluteString, privacy: .public)
        """)
    }
  }

  /// Resolve an `href` from the document against `documentURL`'s
  /// directory. Returns the resulting URL, or nil if the input is
  /// nonsensical.
  private func resolve(href: String) -> URL? {
    if let absolute = URL(string: href),
       let scheme = absolute.scheme, !scheme.isEmpty,
       absolute.scheme != "file" || href.hasPrefix("file:")
    {
      // Absolute URL with an explicit scheme (https://, mailto:, etc.).
      return absolute
    }

    guard let documentURL else { return nil }
    let baseDir = documentURL.deletingLastPathComponent()

    // Strip a query/fragment for path resolution; webkit handles them
    // again on the loaded doc (we only care about which file to open).
    let path: String
    if let pivot = href.firstIndex(where: { $0 == "?" || $0 == "#" }) {
      path = String(href[..<pivot])
    } else {
      path = href
    }
    if path.isEmpty { return nil }

    let decoded = path.removingPercentEncoding ?? path
    if decoded.hasPrefix("/") {
      return URL(fileURLWithPath: decoded).standardized
    }
    return URL(fileURLWithPath: decoded, relativeTo: baseDir)
      .standardized
  }
}
