import Foundation

/// Evidence belonging to one UDP endpoint; socket/timeout ownership stays in the shell.
public struct DatalinkHandshakeAdmission: Sendable {
    private var epoch = 0
    public private(set) var acknowledged = false
    private var window: UInt16?

    public init() {}

    public mutating func reset(epoch: Int) {
        guard epoch >= self.epoch else { return }
        self.epoch = epoch
        acknowledged = false
        window = nil
    }

    public mutating func receive(_ bytes: [UInt8], epoch: Int) {
        guard epoch == self.epoch else { return }
        if DumlTransport.isHandshake(bytes) { acknowledged = true }
        if window == nil { window = MulticamCommands.controlSequence(fromInitialWindow: bytes) }
    }

    public var initialCommandSequence: UInt16? {
        guard acknowledged else { return nil }
        return window
    }

    public var hasInitialWindow: Bool { window != nil }
}
