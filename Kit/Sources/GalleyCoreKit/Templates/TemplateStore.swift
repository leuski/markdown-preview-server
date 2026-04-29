import Foundation
import Observation
import ALFoundation
import AppKit

@Observable
@MainActor
public final class TemplateStore {
  public private(set) var templates: [any Template] = []

  @ObservationIgnored public let directoryURL: URL
  @ObservationIgnored private var watcherTask: Task<Void, Never>?

  public init() {
    self.directoryURL = URL.ourApplicationSupportDirectory / "Templates"

    // Non-fatal: built-in template still works if this fails.
    try? directoryURL.createDirectory()

    reload()
    startWatching()
  }

  public func template(forID id: String) -> (any Template)? {
    templates.first { $0.id == id }
  }

  public func revealFolder() {
    NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
  }

  public func reload() {
    let manager = FileManager.default
    let listingDir = directoryURL.safe
    let contents = (try? manager.contentsOfDirectory(
      at: listingDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])) ?? []

    let discovered: [any Template] = contents.compactMap(makeTemplate(at:))
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name)
        == .orderedAscending }

    let combined: [any Template] = [BuiltInTemplate.shared] + discovered
    if combined.map(\.id) != templates.map(\.id) {
      templates = combined
    }
  }

  private func makeTemplate(at url: URL) -> UserTemplate? {
    let resolved = url.safe

    if resolved.directoryExists {
      // Folder template: must contain Template.html (or template.html).
      for candidate in ["Template.html", "template.html"] {
        let html = resolved / candidate
        if html.itemExists {
          let name = url.lastPathComponent
          return UserTemplate(
            id: name,
            name: name,
            directoryURL: resolved,
            htmlURL: html)
        }
      }
      return nil
    }

    guard resolved.itemExists else { return nil }

    // File template: a top-level .html or .htm file (BBEdit convention).
    let ext = resolved.pathExtension.lowercased()
    guard ext == "html" || ext == "htm" else { return nil }

    let baseName = url.fileName
    return UserTemplate(
      id: baseName,
      name: baseName,
      directoryURL: resolved.parent,
      htmlURL: resolved)
  }

  private func startWatching() {
    let url = directoryURL
    watcherTask = Task { [weak self] in
      var debounce: Task<Void, Never>?
      for await _ in url.fileEvents(eventMask: .all) {
        guard self != nil else { break }
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
          try? await Task.sleep(for: .milliseconds(150))
          guard !Task.isCancelled else { return }
          self?.reload()
        }
      }
    }
  }
}
