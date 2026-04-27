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
        if let stale = model.preferredButUnavailableEntry {
          Text(staleMessage(for: stale, fallback: activeDisplayName))
            .fixedSize(horizontal: true, vertical: false)
        }
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
  private func rendererButton(_ entry: RendererEntry) -> some View {
    // we want
    // 1. text show as disabled as needed
    // 2. items align across built-in and non-built-in groups
    Toggle(entry.displayName, isOn: Binding(
      get: { entry.id == activeID },
      set: { _ in model.selectedRendererID = entry.id }
    ))
    .disabled(!entry.isAvailable)
  }

  @ViewBuilder
  private func rendererSection(_ entries: [RendererEntry]) -> some View {
    ForEach(entries) { entry in
      rendererButton(entry)
    }
  }

  @ViewBuilder
  private var rendererPicker: some View {
    Menu {
      rendererSection(model.rendererEntries.filter({$0.isBuiltIn}))
      Divider()
      rendererSection(model.rendererEntries.filter({!$0.isBuiltIn}))
    } label: {
      Text(activeDisplayName)
    }
    .fixedSize()
  }

  private var activeID: String? {
    model.activeEntry?.id
  }

  private var activeDisplayName: String {
    model.activeEntry?.displayName ?? "No processor available"
  }

  private func staleMessage(
    for entry: RendererEntry, fallback: String) -> String
  {
    "\(entry.displayName) is not installed — using \(fallback)."
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

#Preview {
  SettingsView(model: AppModel())
}
