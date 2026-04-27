import Foundation

extension String {
  var percentEncodedForPath: String {
    addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
  }
}

extension URL {
  var safe: URL {
    standardizedFileURL.resolvingSymlinksInPath()
  }
}
