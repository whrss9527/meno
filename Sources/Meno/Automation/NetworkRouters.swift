import Foundation
import MenoCore

/// Finds the routers of the networks the Mac is on, by their hardware
/// address. Unlike the Wi-Fi network's name, this needs no permission and
/// works for Ethernet too. Nothing is sent: `route` and `arp` only read what
/// macOS already knows.
enum NetworkRouters {
    /// The routers of the networks the Wi-Fi and Ethernet interfaces are
    /// on. Each interface is asked for its own default route, so that a
    /// VPN, which takes over the Mac's default route, does not hide them.
    static func current() async -> Set<String> {
        await Task.detached(priority: .utility) {
            var routers: Set<String> = []
            for interface in activeInterfaces() {
                guard let route = output(of: "/sbin/route", ["-n", "get", "-ifscope", interface, "default"]),
                      let gateway = NetworkIdentity.gateway(inRouteOutput: route),
                      let arp = output(of: "/usr/sbin/arp", ["-n", gateway]),
                      let router = NetworkIdentity.hardwareAddress(inARPOutput: arp)
                else { continue }
                routers.insert(router)
            }
            return routers
        }.value
    }

    /// Names of the interfaces that are up, such as `en0` for Wi-Fi.
    private static func activeInterfaces() -> [String] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
        defer { freeifaddrs(addresses) }
        var names: Set<String> = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = pointer.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_RUNNING) != 0 else { continue }
            let name = String(cString: pointer.pointee.ifa_name)
            if name.hasPrefix("en") {
                names.insert(name)
            }
        }
        return names.sorted()
    }

    private static func output(of path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
