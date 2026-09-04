import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct LocalVPNFilterTests {
    @Test func liveHintWaitsForStallWithoutPicture() {
        #expect(
            !LocalVPNFilter.shouldHintOnLiveWait(
                vpnActive: true, hadVideo: false, secondsWithoutVideo: 7))
        #expect(
            LocalVPNFilter.shouldHintOnLiveWait(
                vpnActive: true, hadVideo: false, secondsWithoutVideo: 8))
        #expect(
            !LocalVPNFilter.shouldHintOnLiveWait(
                vpnActive: true, hadVideo: true, secondsWithoutVideo: 30))
        #expect(
            !LocalVPNFilter.shouldHintOnLiveWait(
                vpnActive: false, hadVideo: false, secondsWithoutVideo: 30))
    }

    @Test func tunnelInterfaceNames() {
        #expect(LocalVPNFilter.isTunnelInterface("utun2"))
        #expect(LocalVPNFilter.isTunnelInterface("ipsec0"))
        #expect(LocalVPNFilter.isTunnelInterface("ppp0"))
        #expect(LocalVPNFilter.isTunnelInterface("tap0"))
        #expect(!LocalVPNFilter.isTunnelInterface("en0"))
        #expect(!LocalVPNFilter.isTunnelInterface("wlan0"))
        #expect(!LocalVPNFilter.isTunnelInterface("lo0"))
    }

    @Test func operatorCopyDoesNotNameSisterApps() {
        let facing = [
            LocalVPNFilter.wizardBanner,
            LocalVPNFilter.liveHint,
            LocalVPNFilter.joinWifiPhoneStep,
        ]
        for text in facing {
            #expect(!text.localizedCaseInsensitiveContains("OpenZCine"))
            #expect(!text.localizedCaseInsensitiveContains("Nikon"))
            #expect(!text.localizedCaseInsensitiveContains("Mimo"))
            #expect(!text.localizedCaseInsensitiveContains("AdGuard"))
            #expect(!text.localizedCaseInsensitiveContains("Blokada"))
        }
    }
}
