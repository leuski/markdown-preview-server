import Foundation

protocol Template: Identifiable, Sendable {
  var id: String { get }
  var name: String { get }
  func loadHTML() throws -> String
  func rewriteAssets(in html: String, origin: String) -> String
  func resolveAsset(file: String) -> URL?
}

struct BuiltInTemplate: Template {
  static let id = "__builtin__"
  static let name = "(Default)"
  static let shared = BuiltInTemplate()

  var id: String { Self.id }
  var name: String { Self.name }

  func loadHTML() throws -> String { Self.html }

  func rewriteAssets(in html: String, origin: String) -> String { html }

  func resolveAsset(file: String) -> URL? { nil }

  private static let html: String = Bundle.main.requiredString(
    forResource: "DefaultTemplate", withExtension: "html")
}

struct UserTemplate: Template {
  let id: String
  let name: String
  let directoryURL: URL
  let htmlURL: URL

  func loadHTML() throws -> String {
    try String(contentsOf: htmlURL, encoding: .utf8)
  }

  func rewriteAssets(in html: String, origin: String) -> String {
    TemplateAssetRewriter.rewrite(
      html: html, templateID: id, origin: origin)
  }

  func resolveAsset(file: String) -> URL? {
    let normalizedDir = directoryURL
      .standardizedFileURL.resolvingSymlinksInPath()
    let candidate = normalizedDir
      .appendingPathComponent(file)
      .standardizedFileURL
      .resolvingSymlinksInPath()

    let dirPath = normalizedDir.path.hasSuffix("/")
      ? normalizedDir.path
      : normalizedDir.path + "/"
    guard candidate.path.hasPrefix(dirPath) else { return nil }
    return candidate
  }
}
