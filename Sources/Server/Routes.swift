import Foundation
import FlyingFox

enum Routes {
  static let preview = "preview"
  static let template = "template"
  static let events = "events"

  static let markdownExtensions: Set<String> = [
    "md", "markdown", "mdown", "mmd"]

  static let assetExtensions: Set<String> = [
    "txt", "html", "htm",
    "css", "js", "json", "map",
    "svg", "png", "jpg", "jpeg", "gif", "webp", "ico", "bmp", "tiff", "tif",
    "woff", "woff2", "ttf", "otf",
    "mp4", "webm", "mp3", "wav", "ogg",
    "pdf"
  ]

  static func register(
    on server: HTTPServer,
    hostURL: URL,
    templateStore: TemplateStore,
    rendererProvider: @Sendable @escaping () -> (any MarkdownRenderer)?,
    watcher: DocumentWatcher
  ) async {
    let storeRef = TemplateStoreRef(templateStore)

    await server.appendRoute(
      .init(method: .GET, path: "/\(preview)/*")) { request in
        await previewOrAssetResponse(
          request: request,
          hostURL: hostURL,
          templateStore: storeRef,
          renderer: rendererProvider())
      }

    await server.appendRoute(
      .init(method: .GET, path: "/\(template)/*")) { request in
      await templateAssetResponse(request: request, templateStore: storeRef)
    }

    await server.appendRoute(
      .init(method: .GET, path: "/\(events)/*")) { request in
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
    hostURL: URL,
    templateStore: TemplateStoreRef,
    renderer: (any MarkdownRenderer)?
  ) async -> HTTPResponse {
    guard let documentURL = decodeFilePath(
      from: request.path, prefix: "/\(preview)")
    else {
      return HTTPResponses.badRequest("Invalid path")
    }

    let ext = documentURL.pathExtension.lowercased()
    if markdownExtensions.contains(ext) {
      guard let renderer else {
        return HTTPResponses.errorPage(
          title: "No markdown processor configured",
          detail: """
            Install a supported processor (e.g. multimarkdown via Homebrew) \
            and pick it in Settings.
            """,
          source: "")
      }
      return await renderPreview(
        documentURL: documentURL,
        request: request,
        hostURL: hostURL,
        templateStore: templateStore,
        renderer: renderer)
    }
    if assetExtensions.contains(ext) {
      return serveFile(at: documentURL)
    }
    return HTTPResponses.notFound("Unsupported extension: .\(ext)")
  }

  private static func renderPreview(
    documentURL: URL,
    request: HTTPRequest,
    hostURL: URL,
    templateStore: TemplateStoreRef,
    renderer: any MarkdownRenderer
  ) async -> HTTPResponse {
    guard FileManager.default.isReadableFile(atPath: documentURL.path) else {
      return HTTPResponses.notFound("Cannot read \(documentURL.path)")
    }

    let source: String
    do {
      source = try String(contentsOf: documentURL, encoding: .utf8)
    } catch {
      return HTTPResponses.notFound(
        "Cannot read \(documentURL.path): \(error.localizedDescription)")
    }

    let renderedBody: String
    do {
      renderedBody = try await renderer.render(source, baseURL: documentURL)
    } catch {
      return HTTPResponses.errorPage(
        title: "Render error",
        detail: error.localizedDescription,
        source: source)
    }

    let template = await templateStore.selected
    let templateHTML: String
    do {
      templateHTML = try template.loadHTML()
    } catch {
      return HTTPResponses.errorPage(
        title: "Template error",
        detail: """
          Cannot load template '\(template.name)': \
          \(error.localizedDescription)
          """,
        source: renderedBody)
    }

    let origin: URL = request.headers[.host]
      .flatMap { URL(string: "http://\($0)") }
    ?? hostURL
    let processedTemplate = template.rewriteAssets(
      in: templateHTML, origin: origin)
    let context = PlaceholderContext(
      documentContent: renderedBody,
      documentURL: documentURL,
      origin: origin)
    let substituted = context.substitute(into: processedTemplate)
    let withReload = injectReloadScript(
      into: substituted, documentURL: documentURL)

    return HTTPResponse(
      statusCode: .ok,
      headers: [
        .contentType: "text/html; charset=utf-8",
        HTTPHeader("Cache-Control"): "no-store"
      ],
      body: Data(withReload.utf8))
  }

  private static func serveFile(at url: URL) -> HTTPResponse {
    guard FileManager.default.isReadableFile(atPath: url.path) else {
      return HTTPResponses.notFound("File not found: \(url.path)")
    }
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      return HTTPResponses.notFound(error.localizedDescription)
    }
    return HTTPResponse(
      statusCode: .ok,
      headers: [
        .contentType: MIMETypes.mimeType(for: url),
        HTTPHeader("Cache-Control"): "no-store"
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
      return HTTPResponses.badRequest("Invalid template asset path")
    }
    let tail = String(request.path.dropFirst(prefix.count))
    guard let slash = tail.firstIndex(of: "/") else {
      return HTTPResponses.notFound("Missing template id or file")
    }

    let rawID = String(tail[..<slash])
    let rawFile = String(tail[tail.index(after: slash)...])
    let templateID = rawID.removingPercentEncoding ?? rawID
    let file = rawFile.removingPercentEncoding ?? rawFile

    guard let template = await templateStore.template(id: templateID) else {
      return HTTPResponses.notFound("Template not found: \(templateID)")
    }
    guard let assetURL = template.resolveAsset(file: file) else {
      return HTTPResponses.notFound(
        "No such asset in template '\(template.name)': \(file)")
    }
    return serveFile(at: assetURL)
  }

  // MARK: - /events/<path> (SSE)

  private static func eventsResponse(
    request: HTTPRequest,
    watcher: DocumentWatcher
  ) async -> HTTPResponse {
    guard
      let documentURL = decodeFilePath(from: request.path, prefix: "/events"),
      markdownExtensions.contains(documentURL.pathExtension.lowercased())
    else {
      return HTTPResponses.badRequest("Invalid event path")
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
        HTTPHeader("X-Accel-Buffering"): "no"
      ],
      body: body)
  }

  // MARK: - Helpers

  /// Extracts a filesystem path from `request.path` (e.g.
  /// "/preview/Users/foo.md") by stripping `prefix` ("/preview"). Returns
  /// the resolved file URL or nil if the extracted path is not absolute,
  /// escapes the filesystem root, or has no extension.
  private static func decodeFilePath(
    from requestPath: String, prefix: String) -> URL?
  {
    guard requestPath.hasPrefix(prefix) else { return nil }
    let tail = String(requestPath.dropFirst(prefix.count))
    guard tail.hasPrefix("/") else { return nil }

    let decoded = tail.removingPercentEncoding ?? tail
    let url = URL(fileURLWithPath: decoded).safe
    guard url.path.hasPrefix("/") else { return nil }
    return url
  }

  private static func injectReloadScript(
    into html: String, documentURL: URL) -> String
  {
    let encodedPath = documentURL.path.percentEncodedForPath
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

}

private struct TemplateStoreRef: Sendable {
  private let store: TemplateStore

  init(_ store: TemplateStore) {
    self.store = store
  }

  var selected: any Template {
    get async { await MainActor.run { store.selected } }
  }

  func template(id: String) async -> (any Template)? {
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
