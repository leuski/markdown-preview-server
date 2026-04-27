import Foundation
import ALFoundation

struct PlaceholderContext: Sendable {
  let documentContent: String
  let documentURL: URL
  let origin: String

  static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .medium
    return formatter
  }()

  func substitute(into template: String, now: Date = Date()) -> String {
    let docDirPath = documentURL.parent.path
    let encodedDir = docDirPath
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    ?? docDirPath
    let trailing = encodedDir.hasSuffix("/") ? "" : "/"
    let baseHref = "\(origin)/preview\(encodedDir)\(trailing)"

    let fileName = documentURL.lastPathComponent
    let baseName = documentURL.fileName
    let ext = documentURL.pathExtension

    let replacements: KeyValuePairs<String, String> = [
      "#DOCUMENT_CONTENT#": documentContent,
      "#TITLE#": htmlEscape(baseName),
      "#BASE#": htmlEscape(baseHref),
      "#FILE#": htmlEscape(fileName),
      "#BASENAME#": htmlEscape(baseName),
      "#FILE_EXTENSION#": htmlEscape(ext),
      "#DATE#": htmlEscape(Self.dateFormatter.string(from: now)),
      "#TIME#": htmlEscape(Self.timeFormatter.string(from: now))
    ]

    var output = template
    for (token, value) in replacements {
      output = output.replacingOccurrences(of: token, with: value)
    }
    return output
  }

  private func htmlEscape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
