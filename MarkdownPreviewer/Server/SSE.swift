import Foundation
import FlyingSocks

struct SSEByteSequence: AsyncBufferedSequence {
  typealias Element = UInt8
  typealias Failure = Never

  let upstream: AsyncStream<Data>

  func makeAsyncIterator() -> Iterator {
    Iterator(upstreamIterator: upstream.makeAsyncIterator(), buffer: [])
  }

  struct Iterator: AsyncBufferedIteratorProtocol {
    typealias Element = UInt8
    typealias Failure = Never

    var upstreamIterator: AsyncStream<Data>.Iterator
    var buffer: [UInt8]

    mutating func next() async -> UInt8? {
      if let byte = buffer.first {
        buffer.removeFirst()
        return byte
      }
      while buffer.isEmpty {
        guard let next = await upstreamIterator.next() else { return nil }
        buffer = Array(next)
      }
      return buffer.removeFirst()
    }

    mutating func nextBuffer(suggested count: Int) async throws -> [UInt8]? {
      if !buffer.isEmpty {
        let take = buffer
        buffer.removeAll(keepingCapacity: false)
        return take
      }
      guard let next = await upstreamIterator.next() else { return nil }
      return Array(next)
    }
  }
}

enum SSE {
  static func encode(event: String? = nil, data: String) -> Data {
    var out = ""
    if let event { out += "event: \(event)\n" }
    for line in data.split(separator: "\n", omittingEmptySubsequences: false) {
      out += "data: \(line)\n"
    }
    out += "\n"
    return Data(out.utf8)
  }

  static let keepAlive = Data(": keepalive\n\n".utf8)
}
