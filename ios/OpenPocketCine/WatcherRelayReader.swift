import Foundation
import Network
import OpenPocketViewCore

/// TCP framing and HEVC copies stay off MainActor. One receive batch at a time: the next
/// read waits for consumption, so a busy decoder cannot accumulate unbounded actor tasks.
final class WatcherRelayReader: @unchecked Sendable {
    enum Message: Sendable {
        case control(WatcherRelayFraming.Decoded)
        case frame(WatcherRelayFrameMetadata, [UInt8])
    }

    let queue = DispatchQueue(label: "opc.watcher-relay.receive", qos: .userInitiated)
    private var buffer = Data()

    func receive(
        on connection: NWConnection,
        completion: @escaping ([Message], Bool, Error?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) {
            [self] data, _, complete, error in
            var messages: [Message] = []
            do {
                if let data { buffer.append(data) }
                while let message = try WatcherRelayFraming.decode(from: buffer) {
                    buffer.removeFirst(message.consumedBytes)
                    if message.kind == .frame {
                        let (meta, hevc) = try WatcherRelayFrameBlob.decode(message.payload)
                        messages.append(.frame(meta, [UInt8](hevc)))
                    } else {
                        messages.append(.control(message))
                    }
                }
                completion(messages, complete, error)
            } catch {
                completion([], true, error)
            }
        }
    }
}
