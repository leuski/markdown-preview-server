import Foundation
import Observation
import FlyingFox
import FlyingSocks

@Observable
@MainActor
final class PreviewServerController {
  enum State: Equatable {
    case stopped
    case running(url: URL)
    case failed(message: String)
  }

  private(set) var state: State = .stopped

  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var server: HTTPServer?

  @ObservationIgnored let watcher = DocumentWatcher()

  @ObservationIgnored private let templateStore: TemplateStore
  @ObservationIgnored private let rendererProvider: @Sendable ()
  -> (any MarkdownRenderer)?

  init(
    templateStore: TemplateStore,
    rendererProvider: @escaping @Sendable () -> (any MarkdownRenderer)?
  ) {
    self.templateStore = templateStore
    self.rendererProvider = rendererProvider
  }

  func start(url: URL) {
    stop()

    let store = templateStore
    let provider = rendererProvider
    let watcher = self.watcher

    guard let components = URLComponents(
      url: url, resolvingAgainstBaseURL: false)
    else {
      state = .failed(message: "Cannot resolve url: \(url)")
      return
    }

    let host = components.host ?? AppModel.defaultHost
    let port = components.port.map { port in UInt16(port) }
    ?? AppModel.defaultPort

    var fullComponents = URLComponents()
    fullComponents.scheme = "http"
    fullComponents.host = host
    fullComponents.port = Int(port)

    guard let fullURL = components.url else {
      state = .failed(message: "Cannot resolve url: \(components)")
      return
    }

    let address: sockaddr_in
    do {
      address = try sockaddr_in.inet(ip4: host, port: port)
    } catch {
      state = .failed(message: """
        Cannot create loopback address: \(error.localizedDescription)
        """)
      return
    }
    let server = HTTPServer(address: address)
    self.server = server

    Task { [weak self] in
      await Routes.register(
        on: server,
        templateStore: store,
        rendererProvider: provider,
        watcher: watcher)

      do {
        self?.publish(state: .running(url: fullURL))
        try await server.run()
        self?.publish(state: .stopped)
      } catch {
        self?.publish(state: .failed(message: error.localizedDescription))
      }
    }
  }

  func stop() {
    Task { [server] in
      await server?.stop()
    }
    server = nil
    state = .stopped
  }

  nonisolated private func publish(state: State) {
    Task { @MainActor [weak self] in
      self?.state = state
    }
  }

  var serverURL: URL? {
    guard case .running(let url) = state else { return nil }
    return url
  }
}
