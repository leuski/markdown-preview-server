import Foundation

enum TemplateAssetRewriter {
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

  static func rewrite(html: String, templateID: String, origin: String) -> String {
    let encodedID = templateID
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? templateID
    let templatePrefix = "\(origin)/template/\(encodedID)/"
    let absolutePrefix = "\(origin)/preview"
    var result = rewriteAttributeURLs(
      html: html, templatePrefix: templatePrefix, absolutePrefix: absolutePrefix)
    result = rewriteCSSURLs(
      html: result, templatePrefix: templatePrefix, absolutePrefix: absolutePrefix)
    return result
  }

  private static func rewriteAttributeURLs(
    html: String, templatePrefix: String, absolutePrefix: String
  ) -> String {
    html.replacing(templateAssetRegex) { match in
      let (_, openTag, value, closeTag) = match.output
      let original = String(value)
      let replaced = rewriteAssetURL(
        original,
        templatePrefix: templatePrefix,
        absolutePrefix: absolutePrefix) ?? original
      return "\(openTag)\(replaced)\(closeTag)"
    }
  }

  private static func rewriteCSSURLs(
    html: String, templatePrefix: String, absolutePrefix: String
  ) -> String {
    html.replacing(cssUrlRegex) { match in
      let whole = match.output.0
      let value = match.output.2
      let original = String(value)
      let replaced = rewriteAssetURL(
        original,
        templatePrefix: templatePrefix,
        absolutePrefix: absolutePrefix) ?? original
      let prefix = whole[whole.startIndex..<value.startIndex]
      let suffix = whole[value.endIndex..<whole.endIndex]
      return "\(prefix)\(replaced)\(suffix)"
    }
  }

  private static func rewriteAssetURL(
    _ value: String, templatePrefix: String, absolutePrefix: String
  ) -> String? {
    guard !value.isEmpty else { return nil }

    // Skip BBEdit-style placeholders (e.g. #DOCUMENT_CONTENT#, #BASE#).
    if value.hasPrefix("#"), value.hasSuffix("#"), value.count >= 2 { return nil }
    // Skip in-page anchors.
    if value.hasPrefix("#") { return nil }
    // Skip protocol-relative URLs.
    if value.hasPrefix("//") { return nil }
    // Skip absolute URLs with a scheme.
    if let url = URL(string: value), let scheme = url.scheme, !scheme.isEmpty {
      return nil
    }

    if value.hasPrefix("/") {
      // BBEdit convention: literal absolute filesystem paths. Route through /preview.
      let encoded = value
        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
      return absolutePrefix + encoded
    }

    // Template-relative path. Encode the value to handle spaces, etc.
    let encoded = value
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    return templatePrefix + encoded
  }
}
