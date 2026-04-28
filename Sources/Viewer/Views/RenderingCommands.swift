import GalleyCoreKit
import SwiftUI

/// Format menu — exposes the renderer (markdown processor) and
/// template pickers as menu items so users can switch globally
/// without opening a settings window.
struct RenderingCommands: Commands {
  @Bindable var settings: ViewerSettings

  var body: some Commands {
    CommandMenu("Format") {
      Menu("Markdown Processor") {
        ProcessorMenu(settings: settings)
      }

      Menu("Template") {
        TemplateMenu(settings: settings)
      }
    }
  }
}
