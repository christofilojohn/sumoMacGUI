import Foundation

public struct SubscriptionResult: Sendable {
    public let objectID: String
    public let values: [UInt8: TraCIValue]
}

public struct ContextSubscriptionResult: Sendable {
    public let objectID: String
    public let perObject: [String: [UInt8: TraCIValue]]
}

extension TraCIReader {
    /// Reads a length prefix that may be 1-byte short or 0+I32 extended.
    /// Returns the *content* length following the prefix.
    public mutating func readCommandLengthHeader() throws -> Int {
        let len = Int(try readU8())
        if len == 0 {
            return Int(try readI32())
        }
        return len
    }

    /// Parses one variable-subscription response block. Caller has already consumed
    /// the leading length+responseCmdID (or wants this method to do it — controlled by `consumeHeader`).
    public mutating func readVariableSubscription(consumeHeader: Bool, expectedRespCmd: UInt8?) throws -> (UInt8, SubscriptionResult) {
        if consumeHeader {
            _ = try readCommandLengthHeader()
            let cmd = try readU8()
            if let expected = expectedRespCmd, cmd != expected {
                throw TraCIError.statusError(command: cmd, message: "expected sub resp 0x\(String(expected, radix: 16))")
            }
            let objectID = try readString()
            let n = Int(try readU8())
            var values: [UInt8: TraCIValue] = [:]
            values.reserveCapacity(n)
            for _ in 0..<n {
                let v = try readU8()
                let res = try readU8()
                if res != 0 {
                    let _ = try readTyped()  // skip error description
                    continue
                }
                values[v] = try readTyped()
            }
            return (cmd, SubscriptionResult(objectID: objectID, values: values))
        } else {
            let cmd: UInt8 = expectedRespCmd ?? 0
            let objectID = try readString()
            let n = Int(try readU8())
            var values: [UInt8: TraCIValue] = [:]
            values.reserveCapacity(n)
            for _ in 0..<n {
                let v = try readU8()
                let res = try readU8()
                if res != 0 {
                    let _ = try readTyped()
                    continue
                }
                values[v] = try readTyped()
            }
            return (cmd, SubscriptionResult(objectID: objectID, values: values))
        }
    }
}
