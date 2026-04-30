import Foundation
import GalleyCoreKit
import WebKit
import os
import ALFoundation

/// Custom URL scheme that lets the Viewer's WebView load template
/// assets (CSS, fonts, images) and document-relative files. The
/// scheme mirrors the live HTTP server's routing — `/template/<id>/…`
/// for template-bundled assets, `/preview/<absolute-path>` for files
/// referenced relative to the previewed document — so the existing
/// `Template.rewriteAssets(...)` rewriting logic produces URLs that
/// resolve correctly here too.
///
/// Origin is `mdeye://local`. The Viewer sets the WebPage's `baseURL`
/// to the same origin so any unrewritten relative URLs (e.g. those
/// in inline `<img>` markup the document author wrote) flow through
/// the handler as well.

@MainActor
struct PreviewSchemeHandler: URLSchemeHandler {
  static let scheme = URLScheme("mdeye") !! "Should not happen"
  static let originURL: URL = "mdeye://local"

  /// Reads the active template at request time. Avoids stale state
  /// when the user switches templates: the next asset request picks
  /// up the new directory.
  let templateProvider: @MainActor @Sendable () -> Template

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.leuski.Markdown-Eye",
    category: "PreviewSchemeHandler")

  nonisolated
  func reply(
    for request: URLRequest
  ) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task { @MainActor in
        do {
          let (data, mime) = try resolve(request: request)
          guard let url = request.url else {
            throw URLError(.badURL)
          }
          let response = URLResponse(
            url: url,
            mimeType: mime,
            expectedContentLength: data.count,
            textEncodingName: nil)
          continuation.yield(.response(response))
          continuation.yield(.data(data))
          continuation.finish()
        } catch {
          Self.logger.warning("""
            asset load failed for \
            \(request.url?.absoluteString ?? "?", privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func resolve(request: URLRequest) throws -> (Data, String) {
    guard let url = request.url else { throw URLError(.badURL) }
    guard let route = PreviewRoute(path: url.path) else {
      throw URLError(.unsupportedURL)
    }
    let assetURL = try resolveAssetURL(for: route)
    let data = try Data(contentsOf: assetURL)
    return (data, MIMETypes.mimeType(for: assetURL))
  }

  private func resolveAssetURL(for route: PreviewRoute) throws -> URL {
    switch route {
    case .templateAsset(let id, let file):
      let template = templateProvider()
      guard template.id == id,
            let assetURL = template.resolveAsset(file: file)
      else { throw URLError(.fileDoesNotExist) }
      return assetURL
    case .documentAsset(let absolutePath):
      return URL(fileURLWithPath: absolutePath)
    }
  }
}
