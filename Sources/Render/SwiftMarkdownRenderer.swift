import Foundation
import Markdown

/// Built-in renderer backed by `swiftlang/swift-markdown`. Always available
/// and used as the default fallback when no external processor is selected.
struct SwiftMarkdownRenderer: MarkdownRenderer {
  let id = "swift-markdown"
  let displayName = "Default (swift-markdown)"

  func render(_ source: String, baseURL: URL) async throws -> String {
    let document = Document(parsing: source)
    var visitor = HTMLVisitor()
    visitor.visit(document)
    return visitor.html
  }
}

private struct HTMLVisitor: MarkupVisitor {
  typealias Result = Void

  var html = ""

  mutating func defaultVisit(_ markup: any Markup) {
    visitChildren(of: markup)
  }

  private mutating func visitChildren(of markup: any Markup) {
    for child in markup.children {
      visit(child)
    }
  }

  // MARK: - Block elements

  mutating func visitDocument(_ document: Document) {
    visitChildren(of: document)
  }

  mutating func visitHeading(_ heading: Heading) {
    let level = max(1, min(heading.level, 6))
    html += "<h\(level)>"
    visitChildren(of: heading)
    html += "</h\(level)>\n"
  }

  mutating func visitParagraph(_ paragraph: Paragraph) {
    html += "<p>"
    visitChildren(of: paragraph)
    html += "</p>\n"
  }

  mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
    html += "<blockquote>\n"
    visitChildren(of: blockQuote)
    html += "</blockquote>\n"
  }

  mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
    let langClass = codeBlock.language.flatMap {
      $0.isEmpty ? nil : " class=\"language-\(escapeAttribute($0))\""
    } ?? ""
    html += "<pre><code\(langClass)>"
    html += escapeText(codeBlock.code)
    html += "</code></pre>\n"
  }

  mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) {
    html += htmlBlock.rawHTML
  }

  mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
    html += "<hr>\n"
  }

  mutating func visitOrderedList(_ list: OrderedList) {
    let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
    html += "<ol\(start)>\n"
    visitChildren(of: list)
    html += "</ol>\n"
  }

  mutating func visitUnorderedList(_ list: UnorderedList) {
    html += "<ul>\n"
    visitChildren(of: list)
    html += "</ul>\n"
  }

  mutating func visitListItem(_ listItem: ListItem) {
    html += "<li>"
    if let checked = listItem.checkbox {
      let attr = checked == .checked ? " checked" : ""
      html += "<input type=\"checkbox\" disabled\(attr)> "
    }
    visitChildren(of: listItem)
    html += "</li>\n"
  }

  mutating func visitTable(_ table: Table) {
    let alignments = table.columnAlignments
    html += "<table>\n<thead>\n<tr>\n"
    for (index, child) in table.head.children.enumerated() {
      let alignment = index < alignments.count ? alignments[index] : nil
      html += "<th\(alignmentAttribute(alignment))>"
      visitChildren(of: child)
      html += "</th>\n"
    }
    html += "</tr>\n</thead>\n"
    if !table.body.isEmpty {
      html += "<tbody>\n"
      for rowMarkup in table.body.children {
        html += "<tr>\n"
        for (index, cell) in rowMarkup.children.enumerated() {
          let alignment = index < alignments.count ? alignments[index] : nil
          html += "<td\(alignmentAttribute(alignment))>"
          visitChildren(of: cell)
          html += "</td>\n"
        }
        html += "</tr>\n"
      }
      html += "</tbody>\n"
    }
    html += "</table>\n"
  }

  // MARK: - Inline elements

  mutating func visitText(_ text: Text) {
    html += escapeText(text.string)
  }

  mutating func visitEmphasis(_ emphasis: Emphasis) {
    html += "<em>"
    visitChildren(of: emphasis)
    html += "</em>"
  }

  mutating func visitStrong(_ strong: Strong) {
    html += "<strong>"
    visitChildren(of: strong)
    html += "</strong>"
  }

  mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
    html += "<del>"
    visitChildren(of: strikethrough)
    html += "</del>"
  }

  mutating func visitInlineCode(_ inlineCode: InlineCode) {
    html += "<code>\(escapeText(inlineCode.code))</code>"
  }

  mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
    html += inlineHTML.rawHTML
  }

  mutating func visitLink(_ link: Link) {
    let href = link.destination ?? ""
    let title = link.title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
    html += "<a href=\"\(escapeAttribute(href))\"\(title)>"
    visitChildren(of: link)
    html += "</a>"
  }

  mutating func visitImage(_ image: Image) {
    let src = image.source ?? ""
    let alt = image.plainText
    let title = image.title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
    html += """
      <img src="\(escapeAttribute(src))" alt="\(escapeAttribute(alt))"\(title)>
      """
  }

  mutating func visitLineBreak(_ lineBreak: LineBreak) {
    html += "<br>\n"
  }

  mutating func visitSoftBreak(_ softBreak: SoftBreak) {
    html += "\n"
  }

  // MARK: - Helpers

  private func alignmentAttribute(
    _ alignment: Table.ColumnAlignment?) -> String
  {
    switch alignment {
    case .left: return " style=\"text-align: left\""
    case .center: return " style=\"text-align: center\""
    case .right: return " style=\"text-align: right\""
    case nil: return ""
    }
  }

  private func escapeText(_ value: String) -> String {
    var out = ""
    out.reserveCapacity(value.count)
    for char in value {
      switch char {
      case "&": out += "&amp;"
      case "<": out += "&lt;"
      case ">": out += "&gt;"
      default: out.append(char)
      }
    }
    return out
  }

  private func escapeAttribute(_ value: String) -> String {
    var out = ""
    out.reserveCapacity(value.count)
    for char in value {
      switch char {
      case "&": out += "&amp;"
      case "<": out += "&lt;"
      case ">": out += "&gt;"
      case "\"": out += "&quot;"
      case "'": out += "&#39;"
      default: out.append(char)
      }
    }
    return out
  }
}
