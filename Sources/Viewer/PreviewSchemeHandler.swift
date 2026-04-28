import Foundation
import GalleyCoreKit
import WebKit
import os

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
struct PreviewSchemeHandler: URLSchemeHandler {
  static let scheme = URLScheme("mdeye")
    ?? URLScheme("x-mdeye")!  // swiftlint:disable:this force_unwrapping
  static let originURL = URL(string: "mdeye://local")
    ?? URL(string: "x-mdeye://local")!  // swiftlint:disable:this force_unwrapping

  /// Reads the active template at request time. Avoids stale state
  /// when the user switches templates: the next asset request picks
  /// up the new directory.
  let templateProvider: @MainActor @Sendable () -> any Template

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.leuski.Markdown-Eye",
    category: "PreviewSchemeHandler")

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

  @MainActor
  private func resolve(request: URLRequest) throws -> (Data, String) {
    guard let url = request.url else { throw URLError(.badURL) }
    let path = url.path

    if let after = path.dropPrefix("/template/") {
      return try resolveTemplateAsset(path: after, requestURL: url)
    }
    if let after = path.dropPrefix("/preview/") {
      return try resolvePreviewAsset(path: after, requestURL: url)
    }

    throw URLError(.unsupportedURL)
  }

  @MainActor
  private func resolveTemplateAsset(
    path: String, requestURL: URL
  ) throws -> (Data, String) {
    guard let slash = path.firstIndex(of: "/") else {
      throw URLError(.badURL)
    }
    let id = String(path[..<slash])
    let file = String(path[path.index(after: slash)...])
    let template = templateProvider()
    guard template.id == id, let assetURL = template.resolveAsset(file: file)
    else {
      throw URLError(.fileDoesNotExist)
    }
    let data = try Data(contentsOf: assetURL)
    return (data, MIMETypes.mimeType(for: assetURL))
  }

  private func resolvePreviewAsset(
    path: String, requestURL: URL
  ) throws -> (Data, String) {
    let decoded = path.removingPercentEncoding ?? path
    let absolute = decoded.hasPrefix("/") ? decoded : "/" + decoded
    let fileURL = URL(fileURLWithPath: absolute)
    let data = try Data(contentsOf: fileURL)
    return (data, MIMETypes.mimeType(for: fileURL))
  }
}

private extension String {
  func dropPrefix(_ prefix: String) -> String? {
    hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
  }
}
