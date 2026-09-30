import Foundation
import Testing

@testable import OpenPocketCineMacCore

struct MacLanPathTests {
    @Test func rejectsUnusableAddresses() {
        #expect(!MacLanPath.validAddress("0.0.0.0"))
        #expect(!MacLanPath.validAddress("127.0.0.1"))
        #expect(!MacLanPath.validAddress("224.0.0.1"))
        #expect(!MacLanPath.validAddress("169.254.1.1"))
        #expect(MacLanPath.validAddress("192.168.1.20"))
        #expect(MacLanPath.validAddress("192.168.2.136"))
        #expect(MacLanPath.isCameraAccessPoint("192.168.2.136"))
        #expect(!MacLanPath.isOsmoSoftAP("PREMIUM-4669"))
        #expect(MacLanPath.isOsmoSoftAP("OsmoPocket-3A1B"))
    }

    @Test func picksTheUpEn0AddressAndIgnoresBridgeAndDownInterfaces() {
        let selected = MacLanPath.select([
            .init(name: "bridge0", up: true, ipv4: "192.168.2.1", netmask: "255.255.255.0"),
            .init(name: "en1", up: false, ipv4: "10.0.0.4", netmask: "255.255.255.0"),
            .init(name: "en0", up: true, ipv4: "192.168.1.20", netmask: "255.255.255.0"),
            .init(name: "ap1", up: true, ipv4: "172.20.10.1", netmask: "255.255.255.240"),
        ])
        #expect(selected?.name == "en0")
        #expect(selected?.ipv4 == "192.168.1.20")
    }
}
