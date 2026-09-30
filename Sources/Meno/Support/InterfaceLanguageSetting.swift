import Foundation
import MenoCore

/// Reads and writes the interface language in Meno's own defaults domain.
/// `UserDefaults.standard` would also return the system's languages, so
/// the value is read from the persistent domain alone.
enum InterfaceLanguageSetting {
    /// The language chosen when Meno started, which is the one it shows.
    /// `AppDelegate` reads it first thing, before it can change.
    static let atLaunch = current

    static var current: InterfaceLanguage {
        // Run outside an app bundle, the domain is named after the process.
        let name = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let domain = UserDefaults.standard.persistentDomain(forName: name)
        return InterfaceLanguage(appleLanguages: domain?[InterfaceLanguage.defaultsKey])
    }

    static func set(_ language: InterfaceLanguage) {
        let defaults = UserDefaults.standard
        if let languages = language.appleLanguages {
            defaults.set(languages, forKey: InterfaceLanguage.defaultsKey)
        } else {
            defaults.removeObject(forKey: InterfaceLanguage.defaultsKey)
        }
        Log.app.info("Interface language set to \(language.rawValue, privacy: .public); applies after a relaunch")
    }
}
