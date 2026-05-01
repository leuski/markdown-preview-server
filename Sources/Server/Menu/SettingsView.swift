import SwiftUI
import GalleyCoreKit

struct SettingsView: View {
  @Bindable var model: AppModel

  @State private var portString: String

  init(model: AppModel) {
    self.model = model
    _portString = State(initialValue: String(model.port))
  }

  var body: some View {
    Form {
      Toggle("Launch at login", isOn: $model.launchAtLogin)

      LabeledContent {
        TextField("", text: $portString)
          .labelsHidden()
          .onSubmit { commitPort() }
      } label: {
        Text("Port")
        // String(...), otherwise, you get a comma in the integer.
        Text("""
            Default: \(String(AppModel.defaultPort)). \
            The server binds to \(AppModel.defaultHost) only.
            """)
        // force the subtitle to span the whole row
        .fixedSize(horizontal: true, vertical: false)
      }

      LabeledContent {
        HStack {
          rendererPicker
          rediscoverRenderersButton
        }
      } label: {
        Text("Markdown processor")
      }

      LabeledContent {
        Button("Install scripts…") {
          ScriptInstaller.installScripts(context: [
            "__LOCATION__": model.hostURL.appendingPreviewPath().absoluteString
          ])
        }
      } label: {
        Text("BBEdit integration")
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 480, maxWidth: 480, minHeight: 360)
  }

  @ViewBuilder
  private var rediscoverRenderersButton: some View {
    Button {
      Task { await model.rediscoverRenderers() }
    } label: {
      Image(systemName: "arrow.clockwise")
    }
    .help("""
      Re-run shell-based discovery — useful after installing a new processor.
      """)
  }

  @ViewBuilder
  private var rendererPicker: some View {
    Menu(currentDisplayName) {
      MenuCore(model: model.processors)
    }
    .fixedSize()
  }

  private var currentDisplayName: String {
    model.processors.selected.name
  }

  private func displacedMessage(
    displaced: String, current: String) -> String
  {
    "\(displaced) is not installed — switched to \(current)."
  }

  private func commitPort() {
    guard let value = UInt16(portString), value > 0 else {
      portString = String(model.port)
      return
    }
    model.port = value
  }
}

#Preview {
  SettingsView(model: AppModel(
    templateStore: TemplateStore(),
    processorStore: ProcessorStore()))
}
