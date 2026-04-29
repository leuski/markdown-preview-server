import Foundation

public struct BuiltInTemplate: Template {
  public static let id = "__builtin__"
  public static let name = "Default"
  public static let shared = BuiltInTemplate()

  public var id: String { Self.id }
  public var name: String { Self.name }

  public func loadHTML() throws -> String { Self.html }

  public func rewriteAssets(in html: String, origin: URL) -> String { html }

  public func resolveAsset(file: String) -> URL? { nil }

  private static let html: String = Bundle.module.requiredString(
    forResource: "DefaultTemplate", withExtension: "html")
}
