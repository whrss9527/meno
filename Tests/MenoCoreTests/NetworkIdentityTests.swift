import XCTest
@testable import MenoCore

final class NetworkIdentityTests: XCTestCase {
    func testReadsTheGatewayOfARoute() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.1.1
          interface: en0
              flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
         recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
               0         0         0         0         0         0      1500         0
        """
        XCTAssertEqual(NetworkIdentity.gateway(inRouteOutput: output), "192.168.1.1")
        XCTAssertEqual(NetworkIdentity.interface(inRouteOutput: output), "en0")
        // A route without a router, or through an IPv6 one, names no network here.
        XCTAssertNil(NetworkIdentity.gateway(inRouteOutput: "   route to: default\n  interface: utun3\n"))
        XCTAssertNil(NetworkIdentity.gateway(inRouteOutput: "    gateway: fe80::1%en0\n"))
        XCTAssertNil(NetworkIdentity.gateway(inRouteOutput: "route: writing to routing socket: not in table"))
        XCTAssertNil(NetworkIdentity.gateway(inRouteOutput: "    gateway: 300.1.1.1\n"))
    }

    func testReadsTheRoutersHardwareAddress() {
        XCTAssertEqual(
            NetworkIdentity.hardwareAddress(inARPOutput: "? (192.168.1.1) at a4:2b:b0:1:2:3 on en0 ifscope [ethernet]"),
            "a4:2b:b0:01:02:03"
        )
        XCTAssertEqual(
            NetworkIdentity.hardwareAddress(inARPOutput: "router.lan (10.0.0.1) at 0:11:32:AB:cd:9 on en1 ifscope permanent [ethernet]"),
            "00:11:32:ab:cd:09"
        )
        XCTAssertNil(NetworkIdentity.hardwareAddress(inARPOutput: "? (192.168.1.1) at (incomplete) on en0 ifscope [ethernet]"))
        XCTAssertNil(NetworkIdentity.hardwareAddress(inARPOutput: "192.168.1.1 (192.168.1.1) -- no entry"))
        XCTAssertNil(NetworkIdentity.hardwareAddress(inARPOutput: "? (192.168.1.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]"))
        XCTAssertNil(NetworkIdentity.normalizedHardwareAddress("a4:2b:b0:1:2"))

        // The same address on two interfaces, or not resolved on one of them.
        let twice = """
        ? (192.168.1.1) at (incomplete) on en0 ifscope [ethernet]
        ? (192.168.1.1) at 0:11:32:ab:cd:9 on en7 ifscope [ethernet]
        ? (192.168.1.1) at a4:2b:b0:1:2:3 on en8 ifscope [ethernet]
        """
        XCTAssertNil(NetworkIdentity.hardwareAddress(inARPOutput: twice, interface: "en0"))
        XCTAssertEqual(NetworkIdentity.hardwareAddress(inARPOutput: twice, interface: "en7"), "00:11:32:ab:cd:09")
        XCTAssertEqual(NetworkIdentity.hardwareAddress(inARPOutput: twice, interface: "en8"), "a4:2b:b0:01:02:03")
        XCTAssertEqual(NetworkIdentity.hardwareAddress(inARPOutput: twice), "00:11:32:ab:cd:09")
        XCTAssertEqual(
            NetworkIdentity.identifier(hardwareAddress: "a4:2b:b0:01:02:03", gateway: "192.168.1.1"),
            "a4:2b:b0:01:02:03@192.168.1.1"
        )
        XCTAssertNil(NetworkIdentity.normalizedHardwareAddress("a4:2b:b0:1:2:xyz"))
    }

    func testTheNetworkConditionMatchesItsRouter() {
        let home = RuleCondition.network(router: "a4:2b:b0:01:02:03", name: "Home")
        XCTAssertTrue(home.isSatisfied(by: RuleContext(routers: ["a4:2b:b0:01:02:03", "00:11:32:ab:cd:09"])))
        XCTAssertFalse(home.isSatisfied(by: RuleContext(routers: ["00:11:32:ab:cd:09"])))
        XCTAssertFalse(RuleCondition.network(router: "", name: "Home").isSatisfied(by: RuleContext(routers: [])))
        XCTAssertEqual(home.kind, .network)
        XCTAssertEqual(RuleCondition.Kind.network.defaultCondition, .network(router: "", name: ""))
    }

    func testNetworksAreWatchedOnlyForEnabledRules() {
        var rule = AutomationRule(name: "Home", conditions: [.network(router: "a4:2b:b0:01:02:03", name: "Home")], action: .revealHidden)
        XCTAssertTrue([rule].watchesNetworks)
        rule.isEnabled = false
        XCTAssertFalse([rule].watchesNetworks)
        XCTAssertFalse([AutomationRule(name: "Power", conditions: [.onPower], action: .revealHidden)].watchesNetworks)
    }

    func testTheConditionRoundTrips() throws {
        let rule = AutomationRule(name: "Home", conditions: [.network(router: "a4:2b:b0:01:02:03", name: "Home")], action: .zen)
        let decoded = try JSONDecoder().decode(AutomationRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded.conditions, rule.conditions)
    }
}
