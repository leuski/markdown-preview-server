import SwiftUI
import UniformTypeIdentifiers

/// Read-only document handle for the Viewer. Carries the source text
/// only as a placeholder — the active rendering is driven by the file
/// URL and a fresh on-disk read in `ViewerModel.reload()`. Using the
/// `viewing:` form of `DocumentGroup` keeps the in-memory copy honest.
nonisolated struct ViewerDocument: FileDocument {
  var text: String

  init(text: String = "") {
    self.text = text
  }

  static let readableContentTypes: [UTType] = [
    UTType(importedAs: "net.daringfireball.markdown"),
    UTType.plainText
  ]

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents,
          let string = String(data: data, encoding: .utf8)
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    text = string
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let data = Data(text.utf8)
    return .init(regularFileWithContents: data)
  }
}
