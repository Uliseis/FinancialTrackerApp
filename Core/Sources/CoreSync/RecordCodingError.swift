import Foundation

public enum RecordCodingError: Error, Equatable, Sendable {
    case wrongRecordType(found: String, expected: String)
    case recordNameNotUUID(String)
    case missingField(recordType: String, field: String)
    case invalidValue(recordType: String, field: String, value: String)
}

extension RecordCodingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .wrongRecordType(let f, let e):
            return "expected recordType '\(e)', got '\(f)'"
        case .recordNameNotUUID(let s):
            return "recordID.recordName not a UUID: '\(s)'"
        case .missingField(let r, let f):
            return "\(r) missing required field '\(f)'"
        case .invalidValue(let r, let f, let v):
            return "\(r).\(f) has invalid value '\(v)'"
        }
    }
}
