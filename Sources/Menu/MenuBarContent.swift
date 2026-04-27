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
      Text("Listening on 127.0.0.1:\(String(port))")
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

  private func openInBrowser(documentURL: URL) {
    guard let base = server.serverURL else { return }
    let encoded = documentURL.path
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? documentURL.path
    guard let url = URL(string: base.absoluteString + "/preview" + encoded) else { return }
    NSWorkspace.shared.open(url)
  }
}
