import Foundation

/// One row in the BBEdit-style processor picker. The `renderer` is `nil`
/// when the underlying tool is not installed; the row is still shown so
/// the user can see what is available and how to install it.
public struct Processor: Sendable, Identifiable {
  public let id: String
  public let name: String
  public let installHint: String?
  public let renderer: (any MarkdownRenderer)?

  public var isBuiltIn: Bool { installHint == nil }
  public var isAvailable: Bool { renderer != nil }
}

public enum MarkdownRendererCatalog {
  private struct Spec: Sendable {
    let id: String
    let name: String
    let installHint: String?
    let discover: @Sendable () async -> (any MarkdownRenderer)?
  }

  /// Order is preserved in the picker. The built-in renderer comes first
  /// so the app has a working default before any external tool is found.
  private static let specs: [Spec] = [
    Spec(
      id: "swift-markdown",
      name: "Built-in",
      installHint: nil,
      discover: { SwiftMarkdownRenderer() }),
    Spec(
      id: "multimarkdown",
      name: "MultiMarkdown",
      installHint: "brew install multimarkdown",
      discover: {
        await ExternalProcessRenderer.discover(
          id: "multimarkdown",
          displayName: "MultiMarkdown",
          toolName: "multimarkdown")
      }),
    Spec(
      id: "discount",
      name: "Discount",
      installHint: "brew install discount",
      discover: {
        await ExternalProcessRenderer.discover(
          id: "discount",
          displayName: "Discount",
          toolName: "markdown")
      }),
    Spec(
      id: "pandoc",
      name: "Pandoc",
      installHint: "brew install pandoc",
      discover: {
        await ExternalProcessRenderer.discover(
          id: "pandoc",
          displayName: "Pandoc",
          toolName: "pandoc",
          arguments: ["--from=markdown", "--to=html"])
      }),
    Spec(
      id: "cmark-gfm",
      name: "cmark-gfm",
      installHint: "brew install cmark-gfm",
      discover: {
        await ExternalProcessRenderer.discover(
          id: "cmark-gfm",
          displayName: "cmark-gfm",
          toolName: "cmark-gfm",
          arguments: [
            "--unsafe",
            "--extension", "table",
            "--extension", "strikethrough",
            "--extension", "tasklist",
            "--extension", "autolink"
          ])
      }),
    Spec(
      id: "classic",
      name: "Classic",
      installHint: "Place Markdown.pl on your PATH",
      discover: {
        await ExternalProcessRenderer.discover(
          id: "classic",
          displayName: "Classic (Markdown.pl)",
          toolName: "Markdown.pl")
      })
  ]

  public static func discoverAll() async -> [Processor] {
    var entries: [Processor] = []
    entries.reserveCapacity(specs.count)
    for spec in specs {
      let renderer = await spec.discover()
      entries.append(Processor(
        id: spec.id,
        name: spec.name,
        installHint: spec.installHint,
        renderer: renderer))
    }
    return entries
  }
}
