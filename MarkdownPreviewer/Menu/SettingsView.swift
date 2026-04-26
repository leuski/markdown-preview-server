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
        rendererPicker
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 480, maxWidth: 480, minHeight: 360)
  }

  @ViewBuilder
  private var rendererPicker: some View {
    if model.availableRenderers.isEmpty {
      Text("No markdown processor found on your PATH.")
        .foregroundStyle(.red)
      Text("Install one (e.g. `brew install multimarkdown`) and click Rescan.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("Rescan") {
        Task { await model.rediscoverRenderers() }
      }
    } else {
      Picker(
        "Processor",
        selection: Binding(
          get: { model.selectedRendererID ?? model.availableRenderers.first?.id ?? "" },
          set: { newID in
            if let r = model.availableRenderers.first(where: { $0.id == newID }) {
              model.selectRenderer(r)
            }
          })
      ) {
        ForEach(model.availableRenderers, id: \.id) { renderer in
          Text(renderer.displayName).tag(renderer.id)
        }
      }
      .pickerStyle(.menu)
      Button("Rescan") {
        Task { await model.rediscoverRenderers() }
      }
      .help("Re-run shell-based discovery — useful after installing a new processor.")
    }
  }

  private func commitPort() {
    guard let value = UInt16(portString), value > 0 else {
      portString = String(model.port)
      return
    }
    model.port = value
  }
}
