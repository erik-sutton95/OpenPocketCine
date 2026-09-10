import Testing

@testable import OpenPocketViewCore

struct MulticamDiscoveryTests {
    @Test func respectsActualSubnetAndExcludesActiveCameras() {
        let hosts = MulticamDiscovery.hosts(
            address: "192.168.7.130", mask: "255.255.255.248", excluding: ["192.168.7.132"])
        #expect(hosts == ["192.168.7.129", "192.168.7.131", "192.168.7.133", "192.168.7.134"])
    }

    @Test func crossesOctetsWithoutAssumingSlash24() {
        let hosts = MulticamDiscovery.hosts(address: "10.4.1.10", mask: "255.255.254.0")
        #expect(hosts?.count == 509)
        #expect(hosts?.first == "10.4.0.1")
        #expect(hosts?.last == "10.4.1.254")
        #expect(hosts?.contains("10.4.1.10") == false)
    }

    @Test func rejectsUnboundedMalformedAndNoncontiguousNetworks() {
        for mask in ["255.255.0.0", "255.255.254.128", "255.255.255.255", "bad"] {
            #expect(MulticamDiscovery.hosts(address: "10.1.2.3", mask: mask) == nil)
        }
        #expect(MulticamDiscovery.hosts(address: "10.1.2.999", mask: "255.255.255.0") == nil)
    }
}
