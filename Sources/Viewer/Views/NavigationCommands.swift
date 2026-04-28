import SwiftUI

/// Bridges the active Viewer window's model into the App's command
/// scene so menu items can drive Back/Forward/Reload on whichever
/// document is frontmost.
private struct ViewerModelKey: FocusedValueKey {
  typealias Value = ViewerModel
}

extension FocusedValues {
  var viewerModel: ViewerModel? {
    get { self[ViewerModelKey.self] }
    set { self[ViewerModelKey.self] = newValue }
  }
}

/// Bundle of state the File > Rename… command needs from the
/// frontmost window — the URL to rename plus a callback that lets
/// the window record the new URL with the system Open Recent list
/// and update its WindowGroup presentation value.
struct RenameContext: Equatable {
  let url: URL?
  let apply: @MainActor (URL) -> Void

  static func == (lhs: RenameContext, rhs: RenameContext) -> Bool {
    lhs.url == rhs.url
  }
}

private struct RenameContextKey: FocusedValueKey {
  typealias Value = RenameContext
}

extension FocusedValues {
  var viewerRenameContext: RenameContext? {
    get { self[RenameContextKey.self] }
    set { self[RenameContextKey.self] = newValue }
  }
}

/// Menu items that mirror the toolbar's navigation buttons. Lives in
/// the View menu (replacing the system-provided sidebar group, which
/// the Viewer doesn't use).
struct NavigationCommands: Commands {
  @FocusedValue(\.viewerModel) private var model

  var body: some Commands {
    CommandGroup(after: .toolbar) {
      Divider()

      Button("Back") {
        guard let model else { return }
        Task { await model.goBack() }
      }
      .disabled(!(model?.canGoBack ?? false))
      .keyboardShortcut("[", modifiers: .command)

      Button("Forward") {
        guard let model else { return }
        Task { await model.goForward() }
      }
      .disabled(!(model?.canGoForward ?? false))
      .keyboardShortcut("]", modifiers: .command)

      Button("Reload") {
        guard let model else { return }
        Task { await model.reload() }
      }
      .disabled(model == nil)
      .keyboardShortcut("r", modifiers: .command)
    }
  }
}
