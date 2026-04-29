import GalleyCoreKit
import SwiftUI

/// Format menu — exposes the renderer (markdown processor) and
/// template pickers as menu items so users can switch globally
/// without opening a settings window.
///
/// When `ViewerSettings.enablePerDocumentOverrides` is on, an extra
/// section appears that lets the frontmost window pin its own
/// renderer / template (overriding the global selection).
struct RenderingCommands: Commands {
  @Bindable var settings: ViewerSettings
  @FocusedValue(\.viewerModel) private var model
  @FocusedValue(\.viewerTemplateChoice) private var templateChoice

  var body: some Commands {
    CommandMenu("Format") {
      Menu("Markdown Processor") {
        ProcessorMenu(settings: settings)
      }

      if settings.enablePerDocumentOverrides, let choice = templateChoice {
        Menu("Template") {
          TemplateMenu(model: choice, settings: settings)
        }
      } else {
        Menu("Global Template") {
          TemplateMenu(settings: settings)
        }
      }

      if settings.enablePerDocumentOverrides {
        Divider()

        Menu("Override Processor for This Window") {
          if let model {
            WindowOverrideProcessorMenu(
              settings: settings, model: model)
          } else {
            Text("No active window")
          }
        }
        .disabled(model == nil)
      }
    }
  }
}
