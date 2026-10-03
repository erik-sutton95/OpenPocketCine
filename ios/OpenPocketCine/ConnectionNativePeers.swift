#if DEBUG
import Foundation
import OpenCineDJIApple

/// DEBUG-only SIMULATED OS/native dependencies. The actual shared connection owner executes
/// the workflow; fixture credentials never touch installed stores or the native camera driver.
@MainActor
struct ConnectionNativePeers {
    var transport: DjiAppleConnectionTransport
    var timing: DjiAppleConnectionTiming
    var exchangeTiming: DjiAppleExchangeTiming
    var currentEndpoint: () -> (any DjiAppleConnectionEndpoint)?
    var attach: ((any DjiAppleConnectionEndpoint)?) -> Void
    var registered: (any DjiAppleConnectionEndpoint, DjiAppleConnectionRun.Attempt) -> Void
    var ssid: String?
    var password: String?
    var stationNetwork: MultiviewNetworkStore.Network?
    var persist: (String, String) -> Void
    var forget: () -> Void
}
#endif
