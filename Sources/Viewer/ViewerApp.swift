import SwiftUI

@main
struct ViewerApp: App {
  var body: some Scene {
    DocumentGroup(viewing: ViewerDocument.self) { configuration in
      ContentView(fileURL: configuration.fileURL)
    }
  }
}
