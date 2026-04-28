import Foundation
import Testing
@testable import GalleyCoreKit

@Suite("SwiftMarkdownRenderer")
struct SwiftMarkdownRendererTests {
  private let baseURL = URL(fileURLWithPath: "/tmp/doc.md")

  @Test("Default renderer omits data-source-line attributes")
  func defaultIsUnannotated() async throws {
    let renderer = SwiftMarkdownRenderer()
    let html = try await renderer.render(
      "# Heading\n\nA paragraph.\n", baseURL: baseURL)
    #expect(!html.contains("data-source-line"))
    #expect(html.contains("<h1>"))
    #expect(html.contains("<p>"))
  }

  @Test("Annotated renderer tags blocks with source line")
  func annotatedTagsBlocks() async throws {
    let renderer = SwiftMarkdownRenderer(annotatesSourceLines: true)
    let source = """
      # Heading

      First paragraph.

      Second paragraph.
      """
    let html = try await renderer.render(source, baseURL: baseURL)
    #expect(html.contains("<h1 data-source-line=\"1\">"))
    #expect(html.contains("<p data-source-line=\"3\">"))
    #expect(html.contains("<p data-source-line=\"5\">"))
  }

  @Test("Annotated renderer tags lists, code, and quotes")
  func annotatedTagsBlockLikeStructures() async throws {
    let renderer = SwiftMarkdownRenderer(annotatesSourceLines: true)
    let source = """
      - item one
      - item two

      > quote on line four

      ```
      code line six
      ```
      """
    let html = try await renderer.render(source, baseURL: baseURL)
    #expect(html.contains("<ul data-source-line=\"1\">"))
    #expect(html.contains("<blockquote data-source-line=\"4\">"))
    #expect(html.contains("<pre data-source-line=\"6\">"))
  }
}
