import Foundation

struct BuiltInTemplate: Template {
  static let id = "__builtin__"
  static let name = "(Default)"
  static let shared = BuiltInTemplate()

  var id: String { Self.id }
  var name: String { Self.name }

  func loadHTML() throws -> String { Self.html }

  func rewriteAssets(in html: String, origin: URL) -> String { html }

  func resolveAsset(file: String) -> URL? { nil }

  private static let html: String = Bundle.main.requiredString(
    forResource: "DefaultTemplate", withExtension: "html")
}
