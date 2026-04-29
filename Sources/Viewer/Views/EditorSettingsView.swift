import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings tab for the cmd-click → editor target. A single popup
/// menu lists every preset plus "Custom URL scheme" and "Other
/// application"; the conditional fields below the popup let the user
/// supply a URL template or pick an `.app` bundle.
struct EditorSettingsView: View {
  @Bindable var settings: ViewerSettings

  var body: some View {
    Form {
      Picker("Editor:", selection: kindBinding) {
        ForEach(EditorPreset.allCases) { preset in
          Text(preset.displayName)
            .tag(EditorChoiceKind.preset(preset))
        }
        Divider()
        Text("Custom URL scheme…").tag(EditorChoiceKind.customURL)
        Text("Other application…").tag(EditorChoiceKind.appBundle)
      }
      .pickerStyle(.menu)

      detailFields
    }
    .padding()
    .frame(width: 460)
  }

  @ViewBuilder
  private var detailFields: some View {
    switch settings.editorChoice {
    case .preset:
      EmptyView()

    case .customURL:
      TextField("URL template:", text: customURLBinding)
        .textFieldStyle(.roundedBorder)
        .font(.system(.body, design: .monospaced))
      Text(
        "Use {url}, {path}, and {line} as placeholders."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

    case .appBundle(let appURL):
      LabeledContent("Application:") {
        HStack {
          Text(appURL.deletingPathExtension().lastPathComponent)
          Spacer()
          Button("Choose…") { pickAppBundle() }
        }
      }
      Text(
        "Line numbers are not passed to applications selected this way."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var kindBinding: Binding<EditorChoiceKind> {
    Binding(
      get: { settings.editorChoice.kind },
      set: { newKind in applyKind(newKind) }
    )
  }

  private var customURLBinding: Binding<String> {
    Binding(
      get: {
        if case .customURL(let template) = settings.editorChoice {
          return template
        }
        return ""
      },
      set: { newValue in
        settings.editorChoice = .customURL(template: newValue)
      }
    )
  }

  /// Switch to a new picker kind. Presets apply immediately. Custom
  /// URL seeds itself from BBEdit's template if there's nothing to
  /// preserve. Choosing "Other application…" launches an open panel;
  /// cancelling leaves the previous choice in place.
  private func applyKind(_ kind: EditorChoiceKind) {
    switch kind {
    case .preset(let preset):
      settings.editorChoice = .preset(preset)

    case .customURL:
      if case .customURL = settings.editorChoice { return }
      settings.editorChoice = .customURL(
        template: EditorPreset.bbedit.template)

    case .appBundle:
      if case .appBundle = settings.editorChoice { return }
      pickAppBundle()
    }
  }

  /// Run NSOpenPanel filtered to `.app` bundles. On selection, store
  /// the URL; on cancel, leave `editorChoice` untouched (the popup
  /// will snap back because the binding's getter still returns the
  /// previous kind).
  private func pickAppBundle() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.applicationBundle]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    settings.editorChoice = .appBundle(url)
  }
}
