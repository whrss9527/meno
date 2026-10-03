import Foundation

/// A setting with a fixed set of values, stored by name.
///
/// A name this version does not know, written by a newer version of Meno,
/// reads as ``fallback``. Without it one such value would make all
/// settings unreadable, and Meno would start over with the defaults.
public protocol SettingChoice: RawRepresentable, CaseIterable, Codable where RawValue == String {
    /// The value an unknown name reads as: the setting's default.
    static var fallback: Self { get }
}

extension SettingChoice {
    public init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: name) ?? Self.fallback
    }
}
