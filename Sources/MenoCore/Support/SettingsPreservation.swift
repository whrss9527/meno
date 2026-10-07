import Foundation

/// JSON values retained without interpreting features this version does not know.
enum SettingsJSON: Codable, Equatable, Sendable {
    case null, bool(Bool), string(String), integer(Int64), unsigned(UInt64), number(Decimal)
    case array([SettingsJSON]), object([String: SettingsJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(UInt64.self) { self = .unsigned(v) }
        else if let v = try? c.decode(Decimal.self) { self = .number(v) }
        else if let v = try? c.decode([SettingsJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: SettingsJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .unsigned(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var identity: String? {
        guard case .object(let fields) = self else { return nil }
        if case .string(let id) = fields["id"] { return "id:" + (UUID(uuidString: id)?.uuidString ?? id) }
        if case .string(let key) = fields["itemKey"] { return "item:" + key }
        return nil
    }
}

/// Stores only unknown fields, so normal settings equality and deletion still work.
struct SettingsPreservation: Equatable, Sendable {
    struct Element: Equatable, Sendable {
        var index: Int
        var identity: String?
        var fields: SettingsPreservation
        var opaque: SettingsJSON?
    }

    var unknown: [String: SettingsJSON] = [:]
    var children: [String: SettingsPreservation] = [:]
    var elements: [Element] = []
    var isEmpty: Bool { unknown.isEmpty && children.isEmpty && elements.isEmpty }

    init() {}

    init(original: SettingsJSON, known: SettingsJSON) {
        switch (original, known) {
        case (.object(let original), .object(let known)):
            for (key, value) in original {
                if let current = known[key] {
                    let extra = Self(original: value, known: current)
                    if !extra.isEmpty { children[key] = extra }
                } else {
                    unknown[key] = value
                }
            }
        case (.array(let original), .array(let known)):
            for (index, value) in original.enumerated() {
                let current = value.identity.flatMap { id in known.first { $0.identity == id } }
                    ?? (value.identity == nil && index < known.count ? known[index] : nil)
                if let current {
                    let extra = Self(original: value, known: current)
                    if !extra.isEmpty { elements.append(Element(index: index, identity: value.identity, fields: extra)) }
                } else {
                    // LossyArray skipped this record. Keep it inert and in its original position.
                    elements.append(Element(index: index, identity: value.identity, fields: Self(), opaque: value))
                }
            }
        default: break
        }
    }

    func merging(into known: SettingsJSON) -> SettingsJSON {
        switch known {
        case .object(let known):
            var result = unknown
            for (key, value) in known { result[key] = children[key]?.merging(into: value) ?? value }
            return .object(result)
        case .array(let known):
            var result = known.enumerated().map { index, value in
                let extra = elements.first { element in
                    element.opaque == nil && (value.identity != nil
                        ? element.identity == value.identity : element.identity == nil && element.index == index)
                }
                return extra?.fields.merging(into: value) ?? value
            }
            for extra in elements where extra.opaque != nil {
                if let id = extra.identity, known.contains(where: { $0.identity == id }) { continue }
                result.insert(extra.opaque!, at: min(extra.index, result.count))
            }
            return .array(result)
        default: return known
        }
    }
}
