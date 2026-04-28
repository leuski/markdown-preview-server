import SwiftUI
import WebKit

struct ContentView: View {
  let fileURL: URL?
  @State private var model = ViewerModel()

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
          .keyboardShortcut("[", modifiers: .command)

          Button {
            Task { await model.goForward() }
          } label: {
            Label("Forward", systemImage: "chevron.forward")
          }
          .disabled(!model.canGoForward)
          .keyboardShortcut("]", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await model.reload() }
          } label: {
            Label("Reload", systemImage: "arrow.clockwise")
          }
          .keyboardShortcut("r", modifiers: .command)
        }
      }
      .task(id: fileURL) {
        guard let fileURL else { return }
        await model.bind(to: fileURL)
      }
      .navigationTitle(navigationTitle)
  }

  private var navigationTitle: String {
    let url = model.documentURL ?? fileURL
    return url?.deletingPathExtension().lastPathComponent ?? "Markdown Eye"
  }
}

#Preview {
  ContentView(fileURL: nil)
}
