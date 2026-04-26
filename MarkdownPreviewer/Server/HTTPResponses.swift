import Foundation
import FlyingFox

enum HTTPResponses {
  static func badRequest(_ message: String) -> HTTPResponse {
    plainText(statusCode: .badRequest, message: message)
  }

  static func notFound(_ message: String) -> HTTPResponse {
    plainText(statusCode: .notFound, message: message)
  }

  static func forbidden(_ message: String) -> HTTPResponse {
    plainText(statusCode: .forbidden, message: message)
  }

  static func errorPage(title: String, detail: String, source: String) -> HTTPResponse {
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

  private static func plainText(statusCode: HTTPStatusCode, message: String) -> HTTPResponse {
    HTTPResponse(
      statusCode: statusCode,
      headers: [.contentType: "text/plain; charset=utf-8"],
      body: Data((message + "\n").utf8))
  }

  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
