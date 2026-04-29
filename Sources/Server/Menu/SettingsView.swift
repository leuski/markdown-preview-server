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
        if let stale = model.preferredButUnavailableProcessor {
          Text(staleMessage(for: stale, fallback: activeDisplayName))
            .fixedSize(horizontal: true, vertical: false)
        }
      }

      LabeledContent {
        Button("Install scripts…") {
          ScriptInstaller.installScripts(model: model)
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
    Menu(activeDisplayName) {
      RendererMenu(appModel: model)
    }
    .fixedSize()
  }

  private var activeDisplayName: String {
    model.processors.active.name
  }

  private func staleMessage(
    for entry: Processor, fallback: String) -> String
  {
    "\(entry.name) is not installed — using \(fallback)."
    + (entry.installHint.map { hint in
      " Install with `\(hint)`, then click Rescan."} ?? "")
  }

  private func commitPort() {
    guard let value = UInt16(portString), value > 0 else {
      portString = String(model.port)
      return
    }
    model.port = value
  }
}

struct RendererMenu<Model>: View
where Model: ChoiceModel, Model.Value: ProcessorModel
{
  let model: Model

  var body: some View {
    let values = model.values
    DividedSections(sections: [
      values.filter { $0.kind == .global },
      values.filter { $0.kind == .builtIn },
      values.filter { $0.kind == .userDefined }
    ], id: \.self) { value in
      Toggle(value.name, isOn: model.selectedBinding(value))
        .disabled(!value.isAvailable)
    }
  }
}

extension RendererMenu where Model == ProcessorChoice {
  init(appModel: AppModel) {
    self.init(model: appModel.processors)
  }
}

struct DividedSections<Item, ID, Content: View>: View
where ID: Hashable
{
  let sections: [[Item]]
  let id: KeyPath<Item, ID>
  @ViewBuilder let content: (Item) -> Content

  var body: some View {
    let nonEmpty = sections.filter { !$0.isEmpty }
    ForEach(Array(nonEmpty.enumerated()), id: \.offset) { index, section in
      if index > 0 { Divider() }
      ForEach(section, id: id) { content($0) }
    }
  }
}

#Preview {
  SettingsView(model: AppModel())
}
