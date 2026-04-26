import Foundation

enum MarkdownRendererCatalog {
  /// Discovers all renderers whose underlying tools are installed.
  /// Order is stable so the first entry is a sensible default.
  static func discoverAll() async -> [any MarkdownRenderer] {
    var found: [any MarkdownRenderer] = []
    if let r = await MultiMarkdownRenderer.discover() { found.append(r) }
    return found
  }
}
