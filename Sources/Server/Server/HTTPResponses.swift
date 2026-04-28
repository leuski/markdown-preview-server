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

  static func errorPage(
    title: String, detail: String, source: String) -> HTTPResponse
  {
    let html = errorPageTemplate
      .replacingOccurrences(of: "#TITLE#", with: title.htmlEscaped)
      .replacingOccurrences(of: "#DETAIL#", with: detail.htmlEscaped)
      .replacingOccurrences(of: "#SOURCE#", with: source.htmlEscaped)
    return HTTPResponse(
      statusCode: .internalServerError,
      headers: [.contentType: "text/html; charset=utf-8"],
      body: Data(html.utf8))
  }

  private static let errorPageTemplate: String =
    Bundle.main.requiredString(forResource: "ErrorPage", withExtension: "html")

  private static func plainText(
    statusCode: HTTPStatusCode, message: String) -> HTTPResponse
  {
    HTTPResponse(
      statusCode: statusCode,
      headers: [.contentType: "text/plain; charset=utf-8"],
      body: Data((message + "\n").utf8))
  }

}
