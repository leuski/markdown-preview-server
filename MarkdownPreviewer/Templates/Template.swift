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

  static let builtInHTML: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="utf-8">
        <title>#TITLE#</title>
        <base href="#BASE#">
        <style>
            :root { color-scheme: light dark; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                line-height: 1.55;
                max-width: 48rem;
                margin: 2rem auto;
                padding: 0 1.25rem;
            }
            pre, code { font-family: ui-monospace, SF Mono, Menlo, monospace; }
            pre {
                background: color-mix(in srgb, currentColor 8%, transparent);
                padding: 0.75rem 1rem;
                border-radius: 6px;
                overflow-x: auto;
            }
            code { padding: 0.1em 0.3em; border-radius: 3px;
                   background: color-mix(in srgb, currentColor 10%, transparent); }
            pre code { padding: 0; background: transparent; }
            blockquote {
                border-left: 3px solid color-mix(in srgb, currentColor 25%, transparent);
                padding-left: 1rem; color: color-mix(in srgb, currentColor 70%, transparent);
            }
            img { max-width: 100%; }
            table { border-collapse: collapse; }
            th, td { border: 1px solid color-mix(in srgb, currentColor 20%, transparent);
                     padding: 0.4rem 0.7rem; }
        </style>
    </head>
    <body>
    #DOCUMENT_CONTENT#
    </body>
    </html>
    """
}
