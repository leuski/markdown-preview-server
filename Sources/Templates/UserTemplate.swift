import Foundation

struct UserTemplate: Template {
  let id: String
  let name: String
  let directoryURL: URL
  let htmlURL: URL

  func loadHTML() throws -> String {
    try String(contentsOf: htmlURL, encoding: .utf8)
  }

  struct Rewriter {
    let templatePrefix: String
    let absolutePrefix: String

    init(id: String, origin: String) {
      self.templatePrefix = "\(origin)/template/\(id.percentEncodedForPath)/"
      self.absolutePrefix = "\(origin)/preview"
    }

    func rewriteAssets(in html: String) -> String {
      rewriteCSSURLs(html: rewriteAttributeURLs(html: html))
    }

    // MARK: - Asset URL rewriting

    // Tags that load resources (not navigation links).
    private static let templateAssetRegex = #/
    (?i)
    (<\s*(?:link|script|img|source|track|video|audio|iframe|object|embed)
    \b[^>]*?\b(?:src|href|data)\s*=\s*")
    ([^"]*)
    ("[^>]*>)
    /#

    // url(...) inside <style> blocks. Matches url("…"), url('…'), url(…).
    private static let cssUrlRegex =
    #/(?i)url\(\s*(['"]?)([^'")]+)\1\s*\)/#

    private func rewriteAttributeURLs(html: String) -> String {
      html.replacing(Self.templateAssetRegex) { match in
        let (_, openTag, value, closeTag) = match.output
        let original = String(value)
        let replaced = rewriteAssetURL(original)
        return "\(openTag)\(replaced)\(closeTag)"
      }
    }

    private func rewriteCSSURLs(html: String) -> String {
      html.replacing(Self.cssUrlRegex) { match in
        let whole = match.output.0
        let value = match.output.2
        let original = String(value)
        let replaced = rewriteAssetURL(original)
        let prefix = whole[whole.startIndex..<value.startIndex]
        let suffix = whole[value.endIndex..<whole.endIndex]
        return "\(prefix)\(replaced)\(suffix)"
      }
    }

    private func rewriteAssetURL(_ value: String) -> String {
      guard !value.isEmpty else { return value }

      // Skip BBEdit-style placeholders (e.g. #DOCUMENT_CONTENT#, #BASE#).
      if value.hasPrefix("#"), value.hasSuffix("#"), value.count >= 2 {
        return value
      }
      // Skip in-page anchors.
      if value.hasPrefix("#") { return value }
      // Skip protocol-relative URLs.
      if value.hasPrefix("//") { return value }
      // Skip absolute URLs with a scheme.
      if let url = URL(string: value),
         let scheme = url.scheme, !scheme.isEmpty
      {
        return value
      }

      if value.hasPrefix("/") {
        // BBEdit convention: literal absolute filesystem paths. Route through
        // /preview.
        return absolutePrefix + value.percentEncodedForPath
      }

      // Template-relative path. Encode the value to handle spaces, etc.
      return templatePrefix + value.percentEncodedForPath
    }
  }

  func rewriteAssets(in html: String, origin: String) -> String {
    Rewriter(id: id, origin: origin).rewriteAssets(in: html)
  }

  func resolveAsset(file: String) -> URL? {
    let directoryURL = self.directoryURL.safe

    let candidate = directoryURL.appendingPathComponent(file).safe

    let dirPath = directoryURL.path.hasSuffix("/")
    ? directoryURL.path
    : directoryURL.path + "/"
    guard candidate.path.hasPrefix(dirPath) else { return nil }
    return candidate
  }
}
