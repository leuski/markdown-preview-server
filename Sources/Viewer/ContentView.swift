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
      .task(id: fileURL) {
        guard let fileURL else { return }
        await model.bind(to: fileURL)
      }
      .navigationTitle(navigationTitle)
  }

  private var navigationTitle: String {
    fileURL?.deletingPathExtension().lastPathComponent ?? "Markdown Eye"
  }
}

#Preview {
  ContentView(fileURL: nil)
}
