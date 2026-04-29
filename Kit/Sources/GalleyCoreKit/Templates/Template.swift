import Foundation

public protocol Template: Identifiable, Sendable {
  var id: String { get }
  var name: String { get }
  var isBuiltIn: Bool { get }
  func loadHTML() throws -> String
  func rewriteAssets(in html: String, origin: URL) -> String
  func resolveAsset(file: String) -> URL?
}
