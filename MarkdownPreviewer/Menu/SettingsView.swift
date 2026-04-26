import SwiftUI

struct SettingsView: View {
  @Bindable var model: AppModel

  @State private var portString: String

  init(model: AppModel) {
    self.model = model
    _portString = State(initialValue: String(model.port))
  }

  var body: some View {
    Form {
      Section("Server") {
        TextField("Port", text: $portString)
          .onSubmit { commitPort() }
          .frame(maxWidth: 120)
        Text("Default: 8089. The server binds to 127.0.0.1 only.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("Markdown Processor") {
        TextField("Executable path", text: $model.rendererPath)
        Text("Default: /usr/local/bin/multimarkdown. The processor must read from stdin and write HTML to stdout.")
          .font(.caption)
          .foregroundStyle(.secondary)
        TextField("Extra arguments", text: $model.rendererArgs)
          .help("Whitespace-separated arguments passed to the processor.")
      }
      Section("Templates") {
        Text("Drop template folders into the Application Support directory; symlinks are followed. Each template is a folder containing Template.html.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 360)
  }

  private func commitPort() {
    guard let value = UInt16(portString), value > 0 else {
      portString = String(model.port)
      return
    }
    model.port = value
  }
}
