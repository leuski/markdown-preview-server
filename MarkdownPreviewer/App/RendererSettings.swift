import Foundation
import os

final class RendererSettings: @unchecked Sendable {
  struct Snapshot: Sendable {
    let path: String
    let args: String
  }

  private let lock = OSAllocatedUnfairLock<Snapshot>(initialState: Snapshot(path: "", args: ""))

  func update(path: String, args: String) {
    lock.withLock { $0 = Snapshot(path: path, args: args) }
  }

  func snapshot() -> Snapshot {
    lock.withLock { $0 }
  }
}
