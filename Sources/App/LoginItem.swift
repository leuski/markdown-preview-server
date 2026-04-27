import Foundation
import ServiceManagement
import os

/// Wraps `SMAppService.mainApp` so the rest of the app can ask "is the
/// app set to launch at login?" without importing ServiceManagement.
enum LoginItem {
  private static let logger = Logger(
    subsystem: "net.leuski.MarkdownPreviewer",
    category: "LoginItem")

  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  /// Returns the resulting enabled state. On failure, returns the
  /// current state and logs the error.
  @discardableResult
  static func setEnabled(_ enabled: Bool) -> Bool {
    do {
      if enabled {
        if SMAppService.mainApp.status != .enabled {
          try SMAppService.mainApp.register()
        }
      } else {
        if SMAppService.mainApp.status != .notRegistered {
          try SMAppService.mainApp.unregister()
        }
      }
    } catch {
      logger.error(
        "Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
    }
    return isEnabled
  }
}
