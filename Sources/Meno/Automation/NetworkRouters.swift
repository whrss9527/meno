import Foundation
import MenoCore

/// Finds the networks the Mac is on by their routers. Unlike the Wi-Fi
/// network's name, this needs no permission and works for Ethernet too.
/// Nothing is sent: `route` and `arp` only read what macOS already knows.
enum NetworkRouters {
    /// A network the Mac is on.
    struct Network: Hashable, Sendable {
        let interface: String
        /// See `NetworkIdentity.identifier(hardwareAddress:gateway:)`.
        let identifier: String
    }

    /// One lookup at a time, off the main thread and the task pool.
    private static let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).routers", qos: .utility)

    /// The networks of the Wi-Fi and Ethernet interfaces, the one the Mac
    /// uses to go online first. Each interface is asked for its own default
    /// route, so that a VPN, which takes over the Mac's default route, does
    /// not hide them.
    static func current() async -> [Network] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: lookUp())
            }
        }
    }

    private static func lookUp() -> [Network] {
        var networks: [Network] = []
        for interface in ipv4Interfaces() {
            guard let route = output(of: "/sbin/route", ["-n", "get", "-ifscope", interface, "default"]),
                  let gateway = NetworkIdentity.gateway(inRouteOutput: route),
                  let arp = output(of: "/usr/sbin/arp", ["-n", "-i", interface, gateway]),
                  let address = NetworkIdentity.hardwareAddress(inARPOutput: arp, interface: interface)
            else { continue }
            networks.append(Network(
                interface: interface,
                identifier: NetworkIdentity.identifier(hardwareAddress: address, gateway: gateway)
            ))
        }
        if networks.count > 1,
           let primary = output(of: "/sbin/route", ["-n", "get", "default"]).flatMap(NetworkIdentity.interface(inRouteOutput:)),
           let index = networks.firstIndex(where: { $0.interface == primary }) {
            networks.insert(networks.remove(at: index), at: 0)
        }
        return networks
    }

    /// Names of the `en` interfaces that are up with an IPv4 address, such
    /// as `en0` for Wi-Fi. The members of a Thunderbolt bridge have none.
    private static func ipv4Interfaces() -> [String] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
        defer { freeifaddrs(addresses) }
        var names: Set<String> = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_RUNNING) != 0,
                  entry.ifa_addr?.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            let name = String(cString: entry.ifa_name)
            if name.hasPrefix("en") {
                names.insert(name)
            }
        }
        return names.sorted()
    }

    /// Runs a tool and returns what it printed. Both tools answer at once
    /// from what macOS knows; one that hangs is stopped after two seconds.
    private static func output(of path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // The output is small enough for the pipe, so the tool never waits
        // for it to be read, and reading ends once it exited.
        if exited.wait(timeout: .now() + 2) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
