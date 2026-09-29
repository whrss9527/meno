import Foundation
import os

enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.whrss9527.meno"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let move = Logger(subsystem: subsystem, category: "move")
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let rules = Logger(subsystem: subsystem, category: "rules")
    static let storage = Logger(subsystem: subsystem, category: "storage")
}
