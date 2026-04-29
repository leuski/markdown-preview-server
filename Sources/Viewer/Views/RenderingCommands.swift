import GalleyCoreKit
import SwiftUI

/// Format menu — exposes the renderer (markdown processor) and
/// template pickers as menu items so users can switch globally
/// without opening a settings window.
///
/// When `ViewerSettings.enablePerDocumentOverrides` is on, the same
/// menus drive the frontmost window's per-document choice; the
/// `.global` value at the top of each list represents "Use Global
/// Setting." When the flag is off, the menus drive the global
/// selection directly.
struct RenderingCommands: Commands {
  @Bindable var settings: ViewerSettings
  @FocusedValue(\.viewerTemplates) private var templates
  @FocusedValue(\.viewerProcessors) private var processors

  var body: some Commands {
    CommandMenu("Format") {
      if settings.enablePerDocumentOverrides, let choice = processors {
        Menu("Markdown Processor") {
          ProcessorMenu(model: choice, settings: settings)
        }
      } else {
        Menu("Global Markdown Processor") {
          ProcessorMenu(settings: settings)
        }
      }

      if settings.enablePerDocumentOverrides, let choice = templates {
        Menu("Template") {
          TemplateMenu(model: choice, settings: settings)
        }
      } else {
        Menu("Global Template") {
          TemplateMenu(settings: settings)
        }
      }
    }
  }
}
