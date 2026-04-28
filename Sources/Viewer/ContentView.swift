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
      .onAppear { bindIfNeeded() }
      .onChange(of: fileURL) { bindIfNeeded() }
      .navigationTitle(navigationTitle)
  }

  private var navigationTitle: String {
    fileURL?.deletingPathExtension().lastPathComponent ?? "Markdown Eye"
  }

  private func bindIfNeeded() {
    guard let fileURL, fileURL != model.documentURL else { return }
    model.bind(to: fileURL)
  }
}

#Preview {
  ContentView(fileURL: nil)
}
