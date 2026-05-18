import Foundation

public enum ImportError: Error, Equatable, Sendable {
    case invalidUUID(table: String, id: String, field: String, value: String)
    case invalidDecimal(table: String, id: String, field: String, value: String)
    case invalidDate(table: String, id: String, field: String, value: String)
    case invalidEnum(table: String, id: String, field: String, value: String, valid: [String])
    case orphanReference(table: String, id: String, field: String, referencedId: String)
    case schemaVersionUnsupported(found: Int, supported: Int)
    case duplicateDumpId(table: String, id: String)
}

extension ImportError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidUUID(let t, let id, let f, let v):
            return "[\(t) id=\(id)] invalid UUID at \(f): \(v)"
        case .invalidDecimal(let t, let id, let f, let v):
            return "[\(t) id=\(id)] invalid Decimal at \(f): \(v)"
        case .invalidDate(let t, let id, let f, let v):
            return "[\(t) id=\(id)] invalid Date at \(f): \(v)"
        case .invalidEnum(let t, let id, let f, let v, let valid):
            return "[\(t) id=\(id)] invalid enum \(f)='\(v)' (valid: \(valid))"
        case .orphanReference(let t, let id, let f, let ref):
            return "[\(t) id=\(id)] orphan reference \(f) -> \(ref)"
        case .schemaVersionUnsupported(let f, let s):
            return "Unsupported dump schemaVersion \(f); importer supports \(s)"
        case .duplicateDumpId(let t, let id):
            return "[\(t) id=\(id)] appears twice in dump"
        }
    }
}
