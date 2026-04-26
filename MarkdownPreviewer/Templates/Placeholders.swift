import Foundation

struct PlaceholderContext: Sendable {
  let documentContent: String
  let documentURL: URL
  let origin: String

  static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
  }()

  static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .medium
    return f
  }()

  func substitute(into template: String, now: Date = Date()) -> String {
    let docDirPath = documentURL.deletingLastPathComponent().path
    let encodedDir = docDirPath
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? docDirPath
    let trailing = encodedDir.hasSuffix("/") ? "" : "/"
    let baseHref = "\(origin)/preview\(encodedDir)\(trailing)"

    let fileName = documentURL.lastPathComponent
    let baseName = documentURL.deletingPathExtension().lastPathComponent
    let ext = documentURL.pathExtension

    let replacements: KeyValuePairs<String, String> = [
      "#DOCUMENT_CONTENT#": documentContent,
      "#TITLE#": htmlEscape(baseName),
      "#BASE#": htmlEscape(baseHref),
      "#FILE#": htmlEscape(fileName),
      "#BASENAME#": htmlEscape(baseName),
      "#FILE_EXTENSION#": htmlEscape(ext),
      "#DATE#": htmlEscape(Self.dateFormatter.string(from: now)),
      "#TIME#": htmlEscape(Self.timeFormatter.string(from: now)),
    ]

    var output = template
    for (token, value) in replacements {
      output = output.replacingOccurrences(of: token, with: value)
    }
    return output
  }

  private func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
