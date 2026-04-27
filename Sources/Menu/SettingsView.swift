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
        Text("""
          Default: \(AppModel.defaultPort). \
          The server binds to \(AppModel.defaultHost) only.
          """)
          .font(.caption)
          .foregroundStyle(.secondary)
        Toggle("Launch at login", isOn: $model.launchAtLogin)
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
    LabeledContent("Processor") {
      Menu {
        ForEach(model.rendererEntries) { entry in
          Button {
            model.selectedRendererID = entry.id
          } label: {
            if entry.id == activeID {
              Label(entry.displayName, systemImage: "checkmark")
            } else {
              Text(entry.displayName)
            }
          }
          .disabled(!entry.isAvailable)
        }
      } label: {
        Text(activeDisplayName)
      }
      .fixedSize()
    }

    if let stale = model.preferredButUnavailableEntry {
      let fallback = model.activeEntry?.displayName ?? "no installed processor"
      Text(staleMessage(for: stale, fallback: fallback))
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    Button("Rescan") {
      Task { await model.rediscoverRenderers() }
    }
    .help("""
      Re-run shell-based discovery — useful after installing a new processor.
      """)
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
