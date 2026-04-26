import Foundation
import Observation
import ALFoundation

@Observable
@MainActor
final class TemplateStore {
  private(set) var templates: [Template] = []
  var selectedID: String

  @ObservationIgnored let directoryURL: URL
  @ObservationIgnored private var watcherTask: Task<Void, Never>?

  private static let selectionKey = "MarkdownPreviewer.selectedTemplateID"

  init() {
    self.directoryURL = URL.ourApplicationSupportDirectory / "Templates"
    self.selectedID = UserDefaults.standard.string(forKey: Self.selectionKey)
    ?? Template.builtIn.id

    do {
      try FileManager.default.createDirectory(
        at: directoryURL, withIntermediateDirectories: true)
    } catch {
      // Non-fatal: built-in template still works.
    }

    reload()
    startWatching()
  }

  var selected: Template {
    templates.first { $0.id == selectedID } ?? Template.builtIn
  }

  func select(_ template: Template) {
    selectedID = template.id
    UserDefaults.standard.set(template.id, forKey: Self.selectionKey)
  }

  func reload() {
    let fm = FileManager.default
    let listingDir = directoryURL.resolvingSymlinksInPath()
    let contents = (try? fm.contentsOfDirectory(
      at: listingDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])) ?? []

    let discovered: [Template] = contents.compactMap(makeTemplate(at:))
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    let combined = [Template.builtIn] + discovered
    if combined.map(\.id) != templates.map(\.id) {
      templates = combined
    }
    if !combined.contains(where: { $0.id == selectedID }) {
      selectedID = Template.builtIn.id
    }
  }

  private func makeTemplate(at url: URL) -> Template? {
    let fm = FileManager.default
    let resolved = url.resolvingSymlinksInPath()
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: resolved.path, isDirectory: &isDir) else { return nil }

    if isDir.boolValue {
      // Folder template: must contain Template.html (or template.html).
      for candidate in ["Template.html", "template.html"] {
        let html = resolved / candidate
        if fm.fileExists(atPath: html.path) {
          let name = url.lastPathComponent
          return Template(
            id: name,
            name: name,
            directoryURL: resolved,
            htmlURL: html)
        }
      }
      return nil
    }

    // File template: a top-level .html or .htm file (BBEdit convention).
    let ext = resolved.pathExtension.lowercased()
    guard ext == "html" || ext == "htm" else { return nil }

    let baseName = url.deletingPathExtension().lastPathComponent
    return Template(
      id: baseName,
      name: baseName,
      directoryURL: resolved.deletingLastPathComponent(),
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
