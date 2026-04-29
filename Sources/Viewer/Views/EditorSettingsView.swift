import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GalleyCoreKit

/// Settings tab for the cmd-click → editor target. A single popup
/// menu lists every preset plus "Custom URL scheme" and "Other
/// application"; the conditional fields below the popup let the user
/// supply a URL template or pick an `.app` bundle.
struct EditorSettingsView: View {
  @Bindable var settings: ViewerSettings

  private var applicationName: String? {
    if case let .appBundle(bundle: url) = settings.editorChoice {
      return url.deletingPathExtension().lastPathComponent
    }
    return nil
  }

  @ViewBuilder
  var editorPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Markdown editor", selection: kindBinding) {
        ForEach(EditorPreset.allCases) { preset in
          Text(preset.displayName)
            .tag(EditorChoiceKind.preset(preset))
        }
        Divider()
        Text("Custom URL scheme…").tag(EditorChoiceKind.customURL)
        Text(applicationName ?? "Other application…")
          .tag(EditorChoiceKind.appBundle)
      }
      .pickerStyle(.menu)
      detailFields
    }
  }

  @ViewBuilder
  private var detailFields: some View {
    switch settings.editorChoice {
    case .preset:
      EmptyView()

    case .customURL:
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("URL template")
          Spacer()
          TextField("URL template", text: customURLBinding)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .labelsHidden()
        }
        Text("Use {url}, {path}, and {line} as placeholders.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

    case .appBundle:
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(
            "Line numbers are not passed to applications selected this way."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Spacer()
          Button("Choose Application…") { pickAppBundle() }
        }
      }
    }
  }

  @ViewBuilder
  var openDocumentPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Open document")
        Spacer()
        Picker(selection: $settings.openBehavior) {
          ForEach(OpenBehavior.allCases) { behavior in
            Text(behavior.displayName).tag(behavior)
          }
        } label: {
          EmptyView()
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
      }
      Text("""
            Applies when opening files via Finder, the Open dialog, or \
            Open Recent. With no existing window, a new window is \
            always used.
            """
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var rediscoverRenderersButton: some View {
    Button {
      Task { await settings.rediscoverRenderers() }
    } label: {
      Image(systemName: "arrow.clockwise")
        .frame(width: 16, height: 16)
    }
    .help("""
      Re-run shell-based discovery — useful after installing a new processor.
      """)
  }

  @ViewBuilder
  private var revealTemplatesButton: some View {
    Button {
      settings.revealTemplatesFolder()
    } label: {
      Image(systemName: "folder")
        .frame(width: 16, height: 16)
    }
    .help("""
      Reveal Templates folder in Finder
      """)
  }

  @ViewBuilder
  private var templatePicker: some View {
    Menu {
      TemplateMenuCore(model: settings.templates)
    } label: {
      Text(settings.activeTemplate.name)
    }
  }

  @ViewBuilder
  private var processorPicker: some View {
    Menu {
      ProcessorMenuCore(model: settings.processors)
    } label: {
      Text(settings.activeProcessor?.name ?? "no processor found")
    }
  }

  var body: some View {
    Form {
      Section {
        openDocumentPicker
      }

      Section {
        editorPicker
        LabeledContent {
          Button("Install scripts…") {
            //            ScriptInstaller.installScripts(model: model)
          }
        } label: {
          Text("Integration")
        }

        LabeledContent {
          HStack {
            processorPicker
            rediscoverRenderersButton
          }
        } label: {
          Text("Processor")
        }

        LabeledContent {
          HStack {
            templatePicker
            revealTemplatesButton
          }
        } label: {
          Text("Template")
        }

      }

      Section {
        Toggle(
          "Allow per-window processor and template overrides",
          isOn: $settings.enablePerDocumentOverrides)
        Text(
          "Adds a Format menu section that lets each window pin its own "
          + "Markdown processor or template, overriding the global "
          + "selection."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding()
    .formStyle(.grouped)
    .frame(minWidth: 580, maxWidth: 580, minHeight: 360)
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

#Preview {
  EditorSettingsView(settings: ViewerSettings(skipDiscovery: true))
}
