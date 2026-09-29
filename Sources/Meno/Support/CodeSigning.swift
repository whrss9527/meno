import Foundation
import Security

/// What the code signature of this copy of Meno says.
enum CodeSigning {
    /// Whether this copy is signed ad hoc, without a certificate. macOS then
    /// ties Accessibility to this very build, so it is asked for again after
    /// each update.
    static let isAdHoc: Bool = ownSigningInformation().map { certificates(in: $0).isEmpty } ?? true

    /// What a newer copy must satisfy to replace this one: this copy's
    /// designated requirement when it is signed with a certificate. An ad hoc
    /// signature's requirement names this very build, so there is none then.
    static var requirementForUpdates: SecRequirement? {
        guard !isAdHoc, let code = ownStaticCode() else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// The signing identifier of `code`, usually its bundle identifier.
    static func identifier(of code: SecStaticCode) -> String? {
        signingInformation(of: code)?[kSecCodeInfoIdentifier as String] as? String
    }

    private static func ownStaticCode() -> SecStaticCode? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess else { return nil }
        return staticCode
    }

    private static func ownSigningInformation() -> [String: Any]? {
        ownStaticCode().flatMap(signingInformation(of:))
    }

    private static func signingInformation(of code: SecStaticCode) -> [String: Any]? {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess else { return nil }
        return information as? [String: Any]
    }

    private static func certificates(in information: [String: Any]) -> [Any] {
        information[kSecCodeInfoCertificates as String] as? [Any] ?? []
    }
}
