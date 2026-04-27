import Foundation

extension Bundle {
  func requiredString(
    forResource name: String, withExtension ext: String
  ) -> String {
    guard
      let url = url(forResource: name, withExtension: ext),
      let string = try? String(contentsOf: url, encoding: .utf8)
    else {
      fatalError("\(name).\(ext) missing from app bundle")
    }
    return string
  }
}
