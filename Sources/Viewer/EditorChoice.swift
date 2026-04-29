import AppKit
import Foundation
import os

/// A built-in editor whose URL scheme + line-jump format we know.
enum EditorPreset: String, Codable, CaseIterable, Identifiable, Hashable {
  case bbedit
  case textmate
  case vscode
  case sublime
  case zed

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .bbedit:   return "BBEdit"
    case .textmate: return "TextMate"
    case .vscode:   return "Visual Studio Code"
    case .sublime:  return "Sublime Text"
    case .zed:      return "Zed"
    }
  }

  /// URL template with `{url}`, `{path}`, `{line}` placeholders.
  /// `{url}` is the percent-encoded `file://…`; `{path}` is the
  /// percent-encoded absolute filesystem path; `{line}` is the
  /// integer line number, or empty when unknown.
  var template: String {
    switch self {
    case .bbedit:   return "x-bbedit://open?url={url}&line={line}"
    case .textmate: return "txmt://open?url={url}&line={line}"
    case .vscode:   return "vscode://file{path}:{line}"
    case .sublime:  return "subl://open?url={url}&line={line}"
    case .zed:      return "zed://file{path}:{line}"
    }
  }
}

/// User's selected editor target. Persisted as JSON in UserDefaults.
enum EditorChoice: Codable, Hashable {
  case preset(EditorPreset)
  case customURL(template: String)
  case appBundle(URL)

  static let `default` = EditorChoice.preset(.bbedit)

  /// Discriminator used by the settings popup menu.
  var kind: EditorChoiceKind {
    switch self {
    case .preset(let preset): return .preset(preset)
    case .customURL:      return .customURL
    case .appBundle:      return .appBundle
    }
  }
}

/// Picker tag — covers all preset + custom rows in a single popup.
enum EditorChoiceKind: Hashable {
  case preset(EditorPreset)
  case customURL
  case appBundle
}

/// Substitutes `{url}`, `{path}`, `{line}` in a URL template.
/// Values are percent-encoded for their intended URL position.
func substituteEditorTemplate(
  _ template: String,
  fileURL: URL,
  line: Int?
) -> String {
  let allowed = CharacterSet.urlQueryAllowed
    .subtracting(CharacterSet(charactersIn: "&=+?#"))
  let urlEncoded = fileURL.absoluteString
    .addingPercentEncoding(withAllowedCharacters: allowed)
    ?? fileURL.absoluteString
  let pathEncoded = fileURL.path
    .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    ?? fileURL.path
  let lineStr = line.map(String.init) ?? ""
  return template
    .replacingOccurrences(of: "{url}", with: urlEncoded)
    .replacingOccurrences(of: "{path}", with: pathEncoded)
    .replacingOccurrences(of: "{line}", with: lineStr)
}

/// Open `fileURL` in the user's chosen editor, optionally jumping to
/// a specific line. URL-template choices fire `NSWorkspace.open(_:)`
/// on the substituted URL; the app-bundle choice launches the picked
/// `.app` directly via `NSWorkspace.open(_:withApplicationAt:…)` and
/// silently drops the line argument (no portable way to pass it).
@MainActor
func openFileInEditor(
  _ choice: EditorChoice,
  fileURL: URL,
  line: Int? = nil,
  logger: Logger? = nil
) async {
  switch choice {
  case .preset(let preset):
    let urlString = substituteEditorTemplate(
      preset.template, fileURL: fileURL, line: line)
    openURL(urlString, logger: logger)

  case .customURL(let template):
    let urlString = substituteEditorTemplate(
      template, fileURL: fileURL, line: line)
    openURL(urlString, logger: logger)

  case .appBundle(let appURL):
    let configuration = NSWorkspace.OpenConfiguration()
    do {
      _ = try await NSWorkspace.shared.open(
        [fileURL], withApplicationAt: appURL,
        configuration: configuration)
    } catch {
      logger?.error("""
        Failed to open \(fileURL.path, privacy: .public) in \
        \(appURL.path, privacy: .public): \
        \(error.localizedDescription, privacy: .public)
        """)
    }
  }
}

@MainActor
private func openURL(_ string: String, logger: Logger?) {
  guard let url = URL(string: string) else {
    logger?.error("""
      Editor URL is not a valid URL: \(string, privacy: .public)
      """)
    return
  }
  if !NSWorkspace.shared.open(url) {
    logger?.error("""
      No handler accepted editor URL: \(string, privacy: .public)
      """)
  }
}
