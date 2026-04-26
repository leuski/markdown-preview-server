import Foundation

struct Template: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let directoryURL: URL
  let htmlURL: URL

  static let defaultName = "(Default)"

  static let builtIn = Template(
    id: "__builtin__",
    name: defaultName,
    directoryURL: URL(fileURLWithPath: "/"),
    htmlURL: URL(fileURLWithPath: "/"))

  var isBuiltIn: Bool { id == Template.builtIn.id }
}

enum TemplateLoader {
  static let templateFileName = "Template.html"

  static func loadHTML(from template: Template) throws -> String {
    if template.isBuiltIn {
      return Self.builtInHTML
    }
    return try String(contentsOf: template.htmlURL, encoding: .utf8)
  }

  static let builtInHTML: String = {
    guard let url = Bundle.main.url(
      forResource: "DefaultTemplate", withExtension: "html"),
      let html = try? String(contentsOf: url, encoding: .utf8) else {
      fatalError("DefaultTemplate.html missing from app bundle")
    }
    return html
  }()
}
