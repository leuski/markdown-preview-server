import Foundation

protocol Template: Identifiable, Sendable {
  var id: String { get }
  var name: String { get }
  func loadHTML() throws -> String
  func rewriteAssets(in html: String, origin: String) -> String
  func resolveAsset(file: String) -> URL?
}
