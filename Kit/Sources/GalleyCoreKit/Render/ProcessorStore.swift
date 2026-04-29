import Foundation
import Observation

/// Holds the discovered list of markdown processors. Populated by
/// `discover()`, which runs the full async catalog scan.
/// Initial state contains only `Processor.builtIn` so consumers like
/// `ProcessorChoice` always see at least one entry — no optional
/// fallback needed before the first discovery completes.
@Observable
@MainActor
public final class ProcessorStore {
  public private(set) var processors: [Processor]

  public init() {
    self.processors = [.builtIn]
  }

  public func processor(forID id: String) -> Processor? {
    processors.first { $0.id == id }
  }

  public func discover() async {
    self.processors = await MarkdownRendererCatalog.discoverAll()
  }
}
