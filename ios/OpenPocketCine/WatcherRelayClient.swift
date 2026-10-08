import Foundation
import OpenCineApple
import OpenCineAppKitApple
import OpenPocketViewCore

// The real common source owns socket, recovery, decoder admission, observation and retirement.
typealias WatcherRelayClientStatus = RelayWatcherPhase
typealias WatcherRelayClient = MonitorWatcherSource<HevcDecoder>

extension MonitorWatcherSource where Decoder == HevcDecoder {
    convenience init(commandWire: (@MainActor (Data) -> Void)? = nil) {
        let decoder = HevcDecoder(), samples = LiveFrameSampleBus()
        self.init(decoder: decoder, samples: samples,
            versionMismatchReason: WatcherRelayJoin.versionMismatchReason,
            journal: { ControlLiveLog.line($0) }, commandWire: commandWire)
        preparePicture = { [weak self, weak decoder, weak samples] in
            guard let self, let decoder, let samples else { return }
            decoder.bindSourcePublication(samples)
            decoder.effectsProvider = nil
            decoder.transferProvider = { [weak self] in self?.transfer }
        }
    }
    var colorMode: ColorMode? { ColorMode(label: state.color) }
    var transfer: MonitorTransfer? { colorMode.map(MonitorTransfer.init) }
}
