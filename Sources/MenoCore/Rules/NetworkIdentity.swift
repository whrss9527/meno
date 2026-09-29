import Foundation

/// Tells networks apart by their router: its hardware address together
/// with its IPv4 address, since a guest network often shares the address
/// of its router's main network, and some routers share a well-known
/// virtual hardware address.
///
/// macOS only gives apps the name of the Wi-Fi network with Location
/// Services, while the router's address is in the ARP table that anyone may
/// read, for Wi-Fi and Ethernet alike, without sending anything. Networks
/// with only IPv6 are not recognized.
public enum NetworkIdentity {
    /// How a network is stored in a rule, for example
    /// `a4:2b:b0:01:02:03@192.168.1.1`.
    public static func identifier(hardwareAddress: String, gateway: String) -> String {
        "\(hardwareAddress)@\(gateway)"
    }

    /// The IPv4 gateway in the output of `route -n get default`.
    public static func gateway(inRouteOutput output: String) -> String? {
        value(of: "gateway", inRouteOutput: output).flatMap { isIPv4($0) ? $0 : nil }
    }

    /// The interface in the output of `route -n get default`, such as `en0`.
    public static func interface(inRouteOutput output: String) -> String? {
        value(of: "interface", inRouteOutput: output)
    }

    /// The hardware address in the output of `arp -n <address>`, for
    /// example `? (192.168.1.1) at a4:2b:b0:1:2:3 on en0 ifscope [ethernet]`.
    /// With `interface`, only an entry on that interface counts: the same
    /// address can be known on several interfaces.
    public static func hardwareAddress(inARPOutput output: String, interface: String? = nil) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            if let interface {
                guard let on = words.firstIndex(of: "on"), words.index(after: on) < words.endIndex,
                      words[words.index(after: on)] == interface
                else { continue }
            }
            guard let at = words.firstIndex(of: "at"), words.index(after: at) < words.endIndex,
                  let address = normalizedHardwareAddress(String(words[words.index(after: at)]))
            else { continue }
            return address
        }
        return nil
    }

    private static func value(of key: String, inRouteOutput output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == key, !parts[1].isEmpty {
                return parts[1]
            }
        }
        return nil
    }

    /// A hardware address as six lowercase two-digit groups, or `nil` for
    /// anything else, including the broadcast and all-zero addresses.
    public static func normalizedHardwareAddress(_ text: String) -> String? {
        let groups = text.split(separator: ":", omittingEmptySubsequences: false)
        guard groups.count == 6 else { return nil }
        var normalized: [String] = []
        for group in groups {
            guard (1...2).contains(group.count), group.allSatisfy(\.isHexDigit) else { return nil }
            normalized.append(group.count == 1 ? "0" + group.lowercased() : group.lowercased())
        }
        let address = normalized.joined(separator: ":")
        guard address != "ff:ff:ff:ff:ff:ff", address != "00:00:00:00:00:00" else { return nil }
        return address
    }

    private static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard let value = Int(part), (1...3).contains(part.count) else { return false }
            return (0...255).contains(value)
        }
    }
}

extension Array where Element == AutomationRule {
    /// Whether an enabled rule depends on the network the Mac is on.
    public var watchesNetworks: Bool {
        contains { rule in
            rule.isEnabled && rule.conditions.contains { $0.kind == .network }
        }
    }
}
