import Foundation

/// Tells networks apart by the hardware address of their router.
///
/// macOS only gives apps the name of the Wi-Fi network with Location
/// Services, while the router's address is in the ARP table that anyone may
/// read, for Wi-Fi and Ethernet alike, without sending anything.
public enum NetworkIdentity {
    /// The IPv4 gateway in the output of `route -n get default`.
    public static func gateway(inRouteOutput output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "gateway", isIPv4(parts[1]) else { continue }
            return parts[1]
        }
        return nil
    }

    /// The hardware address in the output of `arp -n <address>`, for
    /// example `? (192.168.1.1) at a4:2b:b0:1:2:3 on en0 ifscope [ethernet]`.
    public static func hardwareAddress(inARPOutput output: String) -> String? {
        let words = output.split(whereSeparator: \.isWhitespace)
        guard let index = words.firstIndex(of: "at"), words.index(after: index) < words.endIndex else { return nil }
        return normalizedHardwareAddress(String(words[words.index(after: index)]))
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
