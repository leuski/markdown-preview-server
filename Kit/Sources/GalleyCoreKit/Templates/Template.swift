import Foundation

public protocol Template: Identifiable, Sendable {
  var id: String { get }
  var name: String { get }
  func loadHTML() throws -> String
  func rewriteAssets(in html: String, origin: URL) -> String
  func resolveAsset(file: String) -> URL?
}

public extension Template where Self == BuiltInTemplate {
  static var `default`: BuiltInTemplate { .shared }
}
