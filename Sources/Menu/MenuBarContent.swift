import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MenuBarContent: View {
  let model: AppModel
  let server: PreviewServerController
  let templateStore: TemplateStore

  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Group {
      statusItem

      Divider()

      templatesMenu

      Divider()

      Button("Open File…") { openFile() }
        .keyboardShortcut("o")

      Button("Reveal Templates Folder") {
        NSWorkspace.shared.activateFileViewerSelecting([templateStore.directoryURL])
      }

      Button("Install BBEdit Scripts…") { installScripts() }

      if let url = server.serverURL {
        Button("Copy Server URL") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
      }

      Divider()

      Button("Settings…") {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
      }
      .keyboardShortcut(",")

      Button("Quit") { NSApplication.shared.terminate(nil) }
        .keyboardShortcut("q")
    }
  }

  @ViewBuilder
  private var statusItem: some View {
    switch server.state {
    case .running(let port):
      Text("Listening on \(AppModel.defaultHost):\(String(port))")
    case .stopped:
      Text("Server stopped")
    case .failed(let message):
      Text("Server error: \(message)")
    }
  }

  @ViewBuilder
  private var templatesMenu: some View {
    Menu("Template") {
      ForEach(templateStore.templates) { template in
        Button {
          templateStore.select(template)
        } label: {
          HStack {
            Text(template.name)
            if template.id == templateStore.selectedID {
              Spacer()
              Image(systemName: "checkmark")
            }
          }
        }
      }
    }
  }

  private func openFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [
      UTType(filenameExtension: "md"),
      UTType(filenameExtension: "markdown"),
      UTType(filenameExtension: "mdown"),
      UTType(filenameExtension: "mmd"),
      UTType.plainText
    ].compactMap { $0 }
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else { return }
    openInBrowser(documentURL: url)
  }

  private func installScripts() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Install"
    panel.title = "Install BBEdit Scripts"
    panel.message = "Choose the destination folder. Defaults to BBEdit's Scripts folder."

    let defaultDestination = ScriptInstaller.defaultBBEditDestination
    panel.directoryURL = nearestExistingDirectory(for: defaultDestination)

    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let destination = panel.url else { return }

    do {
      try ScriptInstaller.install(to: destination, port: model.port)
      NSWorkspace.shared.activateFileViewerSelecting([destination])
    } catch {
      let alert = NSAlert(error: error)
      alert.messageText = "Could not install scripts"
      alert.runModal()
    }
  }

  private func nearestExistingDirectory(for url: URL) -> URL {
    var current = url
    let manager = FileManager.default
    while !manager.fileExists(atPath: current.path) {
      let parent = current.deletingLastPathComponent()
      if parent == current { break }
      current = parent
    }
    return current
  }

  private func openInBrowser(documentURL: URL) {
    guard let base = server.serverURL else { return }
    let encoded = documentURL.path
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? documentURL.path
    guard let url = URL(string: base.absoluteString + "/preview" + encoded) else { return }
    NSWorkspace.shared.open(url)
  }
}
