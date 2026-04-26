import Foundation
import FlyingFox

enum Routes {
  static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mmd"]

  static let assetExtensions: Set<String> = [
    "txt", "html", "htm",
    "css", "js", "json", "map",
    "svg", "png", "jpg", "jpeg", "gif", "webp", "ico", "bmp", "tiff", "tif",
    "woff", "woff2", "ttf", "otf",
    "mp4", "webm", "mp3", "wav", "ogg",
    "pdf",
  ]

  static func register(
    on server: HTTPServer,
    templateStore: TemplateStore,
    rendererProvider: @Sendable @escaping () -> (any MarkdownRenderer)?,
    watcher: DocumentWatcher
  ) async {
    let storeRef = TemplateStoreRef(templateStore)

    await server.appendRoute("GET /preview/*") { request in
      await previewOrAssetResponse(
        request: request,
        templateStore: storeRef,
        renderer: rendererProvider())
    }

    await server.appendRoute("GET /template/*") { request in
      await templateAssetResponse(request: request, templateStore: storeRef)
    }

    await server.appendRoute("GET /events/*") { request in
      await eventsResponse(request: request, watcher: watcher)
    }

    await server.appendRoute("GET /") { _ in
      HTTPResponse(
        statusCode: .ok,
        headers: [.contentType: "text/plain; charset=utf-8"],
        body: Data("MarkdownPreviewer is running.\n".utf8))
    }
  }

  // MARK: - /preview/<path>

  private static func previewOrAssetResponse(
    request: HTTPRequest,
    templateStore: TemplateStoreRef,
    renderer: (any MarkdownRenderer)?
  ) async -> HTTPResponse {
    guard let documentURL = decodeFilePath(from: request.path, prefix: "/preview")
    else {
      return badRequest("Invalid path")
    }

    let ext = documentURL.pathExtension.lowercased()
    if markdownExtensions.contains(ext) {
      guard let renderer else {
        return errorPage(
          title: "No markdown processor configured",
          detail: "Install a supported processor (e.g. multimarkdown via Homebrew) and pick it in Settings.",
          source: "")
      }
      return await renderPreview(
        documentURL: documentURL,
        request: request,
        templateStore: templateStore,
        renderer: renderer)
    }
    if assetExtensions.contains(ext) {
      return serveFile(at: documentURL)
    }
    return notFound("Unsupported extension: .\(ext)")
  }

  private static func renderPreview(
    documentURL: URL,
    request: HTTPRequest,
    templateStore: TemplateStoreRef,
    renderer: any MarkdownRenderer
  ) async -> HTTPResponse {
    guard FileManager.default.isReadableFile(atPath: documentURL.path) else {
      return notFound("Cannot read \(documentURL.path)")
    }

    let source: String
    do {
      source = try String(contentsOf: documentURL, encoding: .utf8)
    } catch {
      return notFound("Cannot read \(documentURL.path): \(error.localizedDescription)")
    }

    let renderedBody: String
    do {
      renderedBody = try await renderer.render(source, baseURL: documentURL)
    } catch {
      return errorPage(
        title: "Render error",
        detail: error.localizedDescription,
        source: source)
    }

    let template = await templateStore.selected
    let templateHTML: String
    do {
      templateHTML = try TemplateLoader.loadHTML(from: template)
    } catch {
      return errorPage(
        title: "Template error",
        detail: "Cannot load template '\(template.name)': \(error.localizedDescription)",
        source: renderedBody)
    }

    let origin = request.headers[.host].map { "http://\($0)" } ?? ""
    let processedTemplate = template.isBuiltIn
      ? templateHTML
      : rewriteTemplateAssets(html: templateHTML, templateID: template.id, origin: origin)
    let context = PlaceholderContext(
      documentContent: renderedBody,
      documentURL: documentURL,
      origin: origin)
    let substituted = context.substitute(into: processedTemplate)
    let withReload = injectReloadScript(into: substituted, documentURL: documentURL)

    return HTTPResponse(
      statusCode: .ok,
      headers: [
        .contentType: "text/html; charset=utf-8",
        HTTPHeader("Cache-Control"): "no-store",
      ],
      body: Data(withReload.utf8))
  }

  private static func serveFile(at url: URL) -> HTTPResponse {
    guard FileManager.default.isReadableFile(atPath: url.path) else {
      return notFound("File not found: \(url.path)")
    }
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      return notFound(error.localizedDescription)
    }
    return HTTPResponse(
      statusCode: .ok,
      headers: [
        .contentType: mimeType(for: url),
        HTTPHeader("Cache-Control"): "no-store",
      ],
      body: data)
  }

  // MARK: - /template/<id>/<file>

  private static func templateAssetResponse(
    request: HTTPRequest,
    templateStore: TemplateStoreRef
  ) async -> HTTPResponse {
    let prefix = "/template/"
    guard request.path.hasPrefix(prefix) else {
      return badRequest("Invalid template asset path")
    }
    let tail = String(request.path.dropFirst(prefix.count))
    guard let slash = tail.firstIndex(of: "/") else {
      return notFound("Missing template id or file")
    }

    let rawID = String(tail[..<slash])
    let rawFile = String(tail[tail.index(after: slash)...])
    let templateID = rawID.removingPercentEncoding ?? rawID
    let file = rawFile.removingPercentEncoding ?? rawFile

    guard let template = await templateStore.template(id: templateID),
          !template.isBuiltIn
    else {
      return notFound("Template not found: \(templateID)")
    }

    guard let assetURL = resolveAsset(in: template.directoryURL, file: file) else {
      return forbidden("Asset path escapes template directory")
    }
    return serveFile(at: assetURL)
  }

  // MARK: - /events/<path> (SSE)

  private static func eventsResponse(
    request: HTTPRequest,
    watcher: DocumentWatcher
  ) async -> HTTPResponse {
    guard let documentURL = decodeFilePath(from: request.path, prefix: "/events"),
          markdownExtensions.contains(documentURL.pathExtension.lowercased())
    else {
      return badRequest("Invalid event path")
    }

    let bodyStream = AsyncStream<Data> { continuation in
      let task = Task {
        continuation.yield(Data(": connected\n\n".utf8))
        let events = await watcher.subscribe(to: documentURL)
        for await _ in events {
          continuation.yield(SSE.encode(event: "reload", data: "ok"))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }

    let body = HTTPBodySequence(from: SSEByteSequence(upstream: bodyStream))

    return HTTPResponse(
      statusCode: .ok,
      headers: [
        .contentType: "text/event-stream",
        HTTPHeader("Cache-Control"): "no-cache",
        HTTPHeader("Connection"): "keep-alive",
        HTTPHeader("X-Accel-Buffering"): "no",
      ],
      body: body)
  }

  // MARK: - Helpers

  /// Extracts a filesystem path from `request.path` (e.g. "/preview/Users/foo.md") by
  /// stripping `prefix` ("/preview"). Returns the resolved file URL or nil if the
  /// extracted path is not absolute, escapes the filesystem root, or has no extension.
  private static func decodeFilePath(from requestPath: String, prefix: String) -> URL? {
    guard requestPath.hasPrefix(prefix) else { return nil }
    let tail = String(requestPath.dropFirst(prefix.count))
    guard tail.hasPrefix("/") else { return nil }

    let decoded = tail.removingPercentEncoding ?? tail
    let url = URL(fileURLWithPath: decoded).standardizedFileURL.resolvingSymlinksInPath()
    guard url.path.hasPrefix("/") else { return nil }
    return url
  }

  private static func resolveAsset(in directory: URL, file: String) -> URL? {
    let normalizedDir = directory.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = normalizedDir
      .appendingPathComponent(file)
      .standardizedFileURL
      .resolvingSymlinksInPath()

    let dirPath = normalizedDir.path.hasSuffix("/")
    ? normalizedDir.path
    : normalizedDir.path + "/"
    guard candidate.path.hasPrefix(dirPath) else { return nil }
    return candidate
  }

  private static func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "txt": return "text/plain; charset=utf-8"
    case "css": return "text/css; charset=utf-8"
    case "js", "map": return "application/javascript; charset=utf-8"
    case "html", "htm": return "text/html; charset=utf-8"
    case "json": return "application/json; charset=utf-8"
    case "svg": return "image/svg+xml"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "ico": return "image/x-icon"
    case "bmp": return "image/bmp"
    case "tiff", "tif": return "image/tiff"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    case "ttf": return "font/ttf"
    case "otf": return "font/otf"
    case "mp4": return "video/mp4"
    case "webm": return "video/webm"
    case "mp3": return "audio/mpeg"
    case "wav": return "audio/wav"
    case "ogg": return "audio/ogg"
    case "pdf": return "application/pdf"
    default: return "application/octet-stream"
    }
  }

  private static func injectReloadScript(into html: String, documentURL: URL) -> String {
    let encodedPath = documentURL.path
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    let script = """
        <script>
        (function() {
          try {
            var src = new EventSource('/events\(encodedPath)');
            src.addEventListener('reload', function() { location.reload(); });
          } catch (e) { console.warn('livereload disabled:', e); }
        })();
        </script>
        """
    if let range = html.range(of: "</body>", options: .caseInsensitive) {
      return html.replacingCharacters(in: range, with: script + "\n</body>")
    }
    return html + "\n" + script
  }

  // MARK: - Template asset rewriting

  // Tags that load resources (not navigation links).
  private static let templateAssetRegex =
    #/(?i)(<\s*(?:link|script|img|source|track|video|audio|iframe|object|embed)\b[^>]*?\b(?:src|href|data)\s*=\s*")([^"]*)("[^>]*>)/#

  // url(...) inside <style> blocks. Matches url("…"), url('…'), url(…).
  private static let cssUrlRegex =
    #/(?i)url\(\s*(['"]?)([^'")]+)\1\s*\)/#

  static func rewriteTemplateAssets(html: String, templateID: String, origin: String) -> String {
    let encodedID = templateID
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? templateID
    let templatePrefix = "\(origin)/template/\(encodedID)/"
    let absolutePrefix = "\(origin)/preview"
    var result = rewriteAttributeURLs(
      html: html, templatePrefix: templatePrefix, absolutePrefix: absolutePrefix)
    result = rewriteCSSURLs(
      html: result, templatePrefix: templatePrefix, absolutePrefix: absolutePrefix)
    return result
  }

  private static func rewriteAttributeURLs(
    html: String, templatePrefix: String, absolutePrefix: String
  ) -> String {
    html.replacing(templateAssetRegex) { match in
      let (_, openTag, value, closeTag) = match.output
      let original = String(value)
      let replaced = rewriteAssetURL(
        original,
        templatePrefix: templatePrefix,
        absolutePrefix: absolutePrefix) ?? original
      return "\(openTag)\(replaced)\(closeTag)"
    }
  }

  private static func rewriteCSSURLs(
    html: String, templatePrefix: String, absolutePrefix: String
  ) -> String {
    html.replacing(cssUrlRegex) { match in
      let whole = match.output.0
      let value = match.output.2
      let original = String(value)
      let replaced = rewriteAssetURL(
        original,
        templatePrefix: templatePrefix,
        absolutePrefix: absolutePrefix) ?? original
      let prefix = whole[whole.startIndex..<value.startIndex]
      let suffix = whole[value.endIndex..<whole.endIndex]
      return "\(prefix)\(replaced)\(suffix)"
    }
  }

  private static func rewriteAssetURL(
    _ value: String, templatePrefix: String, absolutePrefix: String
  ) -> String? {
    guard !value.isEmpty else { return nil }

    // Skip BBEdit-style placeholders (e.g. #DOCUMENT_CONTENT#, #BASE#).
    if value.hasPrefix("#"), value.hasSuffix("#"), value.count >= 2 { return nil }
    // Skip in-page anchors.
    if value.hasPrefix("#") { return nil }
    // Skip protocol-relative URLs.
    if value.hasPrefix("//") { return nil }
    // Skip absolute URLs with a scheme.
    if let url = URL(string: value), let scheme = url.scheme, !scheme.isEmpty {
      return nil
    }

    if value.hasPrefix("/") {
      // BBEdit convention: literal absolute filesystem paths. Route through /preview.
      let encoded = value
        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
      return absolutePrefix + encoded
    }

    // Template-relative path. Encode the value to handle spaces, etc.
    let encoded = value
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    return templatePrefix + encoded
  }

  // MARK: - Response builders

  private static func badRequest(_ message: String) -> HTTPResponse {
    HTTPResponse(
      statusCode: .badRequest,
      headers: [.contentType: "text/plain; charset=utf-8"],
      body: Data((message + "\n").utf8))
  }

  private static func notFound(_ message: String) -> HTTPResponse {
    HTTPResponse(
      statusCode: .notFound,
      headers: [.contentType: "text/plain; charset=utf-8"],
      body: Data((message + "\n").utf8))
  }

  private static func forbidden(_ message: String) -> HTTPResponse {
    HTTPResponse(
      statusCode: .forbidden,
      headers: [.contentType: "text/plain; charset=utf-8"],
      body: Data((message + "\n").utf8))
  }

  private static func errorPage(title: String, detail: String, source: String) -> HTTPResponse {
    let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(title)</title>
        <style>body{font-family:-apple-system,sans-serif;padding:2rem;max-width:60rem;margin:auto}
        pre{background:#f4f4f4;padding:1rem;border-radius:6px;overflow:auto}
        h1{color:#c00}</style></head><body>
        <h1>\(title)</h1><pre>\(escape(detail))</pre>
        <h2>Source</h2><pre>\(escape(source))</pre></body></html>
        """
    return HTTPResponse(
      statusCode: .internalServerError,
      headers: [.contentType: "text/html; charset=utf-8"],
      body: Data(html.utf8))
  }

  private static func escape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}

private struct TemplateStoreRef: Sendable {
  private let store: TemplateStore

  init(_ store: TemplateStore) {
    self.store = store
  }

  var selected: Template {
    get async { await MainActor.run { store.selected } }
  }

  func template(id: String) async -> Template? {
    await MainActor.run { store.templates.first { $0.id == id } }
  }
}

private extension HTTPRequest {
  func query(_ name: String) -> String? {
    for item in query where item.name == name {
      return item.value
    }
    return nil
  }
}
