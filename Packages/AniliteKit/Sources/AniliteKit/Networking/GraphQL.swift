import Foundation

/// Minimal JSON value used for GraphQL variables. Nil variables are never encoded:
/// AniList returns HTTP 500 for some filters when they are sent as explicit nulls.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    /// Stable textual form used for cache keys (sorted object keys).
    public var canonical: String {
        switch self {
        case .string(let v): return "\"\(v)\""
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .array(let v): return "[" + v.map(\.canonical).joined(separator: ",") + "]"
        case .object(let v):
            return "{" + v.keys.sorted().map { "\"\($0)\":\(v[$0]!.canonical)" }.joined(separator: ",") + "}"
        }
    }
}

/// Builder that silently drops nil values.
public struct Variables: Sendable {
    public private(set) var values: [String: JSONValue] = [:]

    public init() {}

    public mutating func set(_ key: String, _ value: Int?) { if let value { values[key] = .int(value) } }
    public mutating func set(_ key: String, _ value: Double?) { if let value { values[key] = .double(value) } }
    public mutating func set(_ key: String, _ value: Bool?) { if let value { values[key] = .bool(value) } }
    public mutating func set(_ key: String, _ value: String?) {
        if let value, !value.isEmpty { values[key] = .string(value) }
    }
    public mutating func set(_ key: String, _ value: [String]?) {
        if let value, !value.isEmpty { values[key] = .array(value.map(JSONValue.string)) }
    }
    public mutating func set(_ key: String, _ value: [Int]?) {
        if let value, !value.isEmpty { values[key] = .array(value.map(JSONValue.int)) }
    }
    public mutating func set<E: RawRepresentable>(_ key: String, _ value: E?) where E.RawValue == String {
        if let value { values[key] = .string(value.rawValue) }
    }
    public mutating func set<E: RawRepresentable>(_ key: String, _ value: [E]?) where E.RawValue == String {
        if let value, !value.isEmpty { values[key] = .array(value.map { .string($0.rawValue) }) }
    }
}

public struct GraphQLOperation<Response: Decodable & Sendable>: Sendable {
    public var name: String
    public var query: String
    public var variables: [String: JSONValue]
    /// How long a cached response is considered fresh.
    public var ttl: TimeInterval
    public var isMutation: Bool
    public var requiresAuth: Bool

    public init(name: String, query: String, variables: Variables = Variables(), ttl: TimeInterval = 600, isMutation: Bool = false, requiresAuth: Bool = false) {
        self.name = name
        self.query = query
        self.variables = variables.values
        self.ttl = ttl
        self.isMutation = isMutation
        self.requiresAuth = requiresAuth
    }

    public var cacheKey: String {
        let vars = JSONValue.object(variables).canonical
        return name + "-" + StableHash.hex(query + "|" + vars)
    }
}

struct GraphQLRequestBody: Encodable {
    let query: String
    let variables: [String: JSONValue]
}

struct GraphQLErrorItem: Decodable {
    let message: String
    let status: Int?
}

struct GraphQLEnvelope<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLErrorItem]?
}

/// FNV-1a 64-bit — deterministic across launches and platforms (unlike Hasher).
public enum StableHash {
    public static func value(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    public static func hex(_ string: String) -> String {
        let v = value(string)
        let s = String(v, radix: 16)
        return String(repeating: "0", count: max(0, 16 - s.count)) + s
    }
}
