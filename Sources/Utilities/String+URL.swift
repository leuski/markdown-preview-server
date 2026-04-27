import Foundation

extension String {
  func percentEncodedForPath() -> String {
    addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
  }
}
