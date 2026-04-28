import Foundation
import ALFoundation
import GalleyCoreKit

struct PlaceholderContext: Sendable {
  let documentContent: String
  let documentURL: URL
  let origin: URL

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
    let baseHref = origin.appendingPreviewPath(docDirPath)
      .absoluteString.appendingSlash

    let fileName = documentURL.lastPathComponent
    let baseName = documentURL.fileName
    let ext = documentURL.pathExtension

    let replacements: KeyValuePairs<String, String> = [
      "#DOCUMENT_CONTENT#": documentContent,
      "#TITLE#": baseName.htmlAttributeEscaped,
      "#BASE#": baseHref.htmlAttributeEscaped,
      "#FILE#": fileName.htmlAttributeEscaped,
      "#BASENAME#": baseName.htmlAttributeEscaped,
      "#FILE_EXTENSION#": ext.htmlAttributeEscaped,
      "#DATE#": Self.dateFormatter.string(from: now).htmlAttributeEscaped,
      "#TIME#": Self.timeFormatter.string(from: now).htmlAttributeEscaped
    ]

    var output = template
    for (token, value) in replacements {
      output = output.replacingOccurrences(of: token, with: value)
    }
    return output
  }
}
