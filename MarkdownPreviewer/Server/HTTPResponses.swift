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
    let html = errorPageTemplate
      .replacingOccurrences(of: "#TITLE#", with: escape(title))
      .replacingOccurrences(of: "#DETAIL#", with: escape(detail))
      .replacingOccurrences(of: "#SOURCE#", with: escape(source))
    return HTTPResponse(
      statusCode: .internalServerError,
      headers: [.contentType: "text/html; charset=utf-8"],
      body: Data(html.utf8))
  }

  private static let errorPageTemplate: String = {
    guard let url = Bundle.main.url(forResource: "ErrorPage", withExtension: "html"),
          let html = try? String(contentsOf: url, encoding: .utf8) else {
      fatalError("ErrorPage.html missing from app bundle")
    }
    return html
  }()

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
