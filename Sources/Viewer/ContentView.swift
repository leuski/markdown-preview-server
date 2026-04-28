import AppKit
import SwiftUI
import WebKit

struct ContentView: View {
  let fileURL: URL?
  @State private var model = ViewerModel()
  @State private var hostWindow: NSWindow?

  var body: some View {
    WebView(model.page)
      .overlay(alignment: .bottom) {
        if let error = model.lastError {
          Text(error)
            .padding(8)
            .background(.regularMaterial, in: .rect(cornerRadius: 8))
            .padding()
        }
      }
      .toolbar {
        ToolbarItemGroup(placement: .navigation) {
          Button {
            Task { await model.goBack() }
          } label: {
            Label("Back", systemImage: "chevron.backward")
          }
          .disabled(!model.canGoBack)
          .help("Back (⌘[)")

          Button {
            Task { await model.goForward() }
          } label: {
            Label("Forward", systemImage: "chevron.forward")
          }
          .disabled(!model.canGoForward)
          .help("Forward (⌘])")
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await model.reload() }
          } label: {
            Label("Reload", systemImage: "arrow.clockwise")
          }
          .help("Reload (⌘R)")
        }
      }
      .focusedSceneValue(\.viewerModel, model)
      .hostingWindow { hostWindow = $0 }
      .task(id: fileURL) {
        guard let fileURL else { return }
        await model.bind(to: fileURL)
      }
      .onChange(of: model.documentURL, initial: true) { _, _ in
        applyWindowTitle()
      }
      .onChange(of: hostWindow) { _, _ in
        applyWindowTitle()
      }
  }

  /// Push the currently-rendered URL into the host window's title bar
  /// and proxy icon. DocumentGroup sets these from the original
  /// FileDocument URL on its own; we override after the fact so that
  /// in-window navigation reflects in the title bar.
  private func applyWindowTitle() {
    guard let hostWindow else { return }
    let url = model.documentURL ?? fileURL
    if let url {
      hostWindow.title = url.deletingPathExtension().lastPathComponent
      hostWindow.representedURL = url.isFileURL ? url : nil
    } else {
      hostWindow.title = "Markdown Eye"
      hostWindow.representedURL = nil
    }
  }
}

#Preview {
  ContentView(fileURL: nil)
}
