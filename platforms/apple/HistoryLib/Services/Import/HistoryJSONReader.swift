import Foundation

/// Reads JSON syntax without retaining an envelope or array. Captured values
/// have a byte budget; skipped values use only the fixed input block and stack.
nonisolated final class HistoryJSONReader {
    private let handle: FileHandle
    private var buffer = Data()
    private var offset = 0
    private var firstMember = true
    private var firstElement = true

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
    }

    deinit { try? handle.close() }

    func beginObject() throws {
        try whitespace()
        // JSONDecoder also accepts an optional UTF-8 BOM.
        if try peek() == 0xEF {
            try expect(0xEF); try expect(0xBB); try expect(0xBF)
        }
        try whitespace()
        try expect(123)
    }

    func nextKey() throws -> String? {
        try whitespace()
        if try peek() == 125 { try expect(125); return nil }
        if !firstMember { try expect(44); try whitespace() }
        firstMember = false
        guard try peek() == 34 else { throw HistoryTransferError.invalidJSON }
        let key = try JSONDecoder().decode(String.self, from: value(maximumBytes: 4_096))
        try whitespace()
        try expect(58)
        return key
    }

    func beginArray() throws {
        try whitespace()
        try expect(91)
        firstElement = true
    }

    func nextElement() throws -> Data? {
        try whitespace()
        if try peek() == 93 { try expect(93); return nil }
        if !firstElement { try expect(44); try whitespace() }
        firstElement = false
        return try value(maximumBytes: HistoryTransferLimits.recordBytes)
    }

    func value(maximumBytes: Int = HistoryTransferLimits.recordBytes) throws -> Data {
        var output: Data? = Data()
        try consumeValue(into: &output, limit: maximumBytes, depth: 0)
        return output!
    }

    func skipValue() throws {
        var output: Data?
        try consumeValue(into: &output, limit: 0, depth: 0)
    }

    func finish() throws {
        try whitespace()
        guard try peek() == nil else { throw HistoryTransferError.invalidJSON }
    }

    private func consumeValue(into output: inout Data?, limit: Int, depth: Int) throws {
        guard depth <= 64 else { throw HistoryTransferError.resourceLimitExceeded }
        try whitespace(into: &output, limit: limit)
        guard let byte = try peek() else { throw HistoryTransferError.invalidJSON }
        switch byte {
        case 34:
            try string(into: &output, limit: limit)
        case 123:
            try take(into: &output, limit: limit)
            try whitespace(into: &output, limit: limit)
            if try peek() != 125 {
                while true {
                    try string(into: &output, limit: limit)
                    try whitespace(into: &output, limit: limit)
                    try expect(58, into: &output, limit: limit)
                    try consumeValue(into: &output, limit: limit, depth: depth + 1)
                    try whitespace(into: &output, limit: limit)
                    if try peek() != 44 { break }
                    try take(into: &output, limit: limit)
                    try whitespace(into: &output, limit: limit)
                }
            }
            try expect(125, into: &output, limit: limit)
        case 91:
            try take(into: &output, limit: limit)
            try whitespace(into: &output, limit: limit)
            if try peek() != 93 {
                while true {
                    try consumeValue(into: &output, limit: limit, depth: depth + 1)
                    try whitespace(into: &output, limit: limit)
                    if try peek() != 44 { break }
                    try take(into: &output, limit: limit)
                }
            }
            try expect(93, into: &output, limit: limit)
        case 116, 102, 110:
            for expected in (byte == 116 ? "true" : byte == 102 ? "false" : "null").utf8 {
                try expect(expected, into: &output, limit: limit)
            }
        case 45, 48...57:
            try number(into: &output, limit: limit)
        default:
            throw HistoryTransferError.invalidJSON
        }
    }

    private func string(into output: inout Data?, limit: Int) throws {
        try expect(34, into: &output, limit: limit)
        while let byte = try peek() {
            guard byte >= 32 else { throw HistoryTransferError.invalidJSON }
            try take(into: &output, limit: limit)
            if byte == 34 { return }
            if byte == 92 {
                guard let escaped = try peek() else { throw HistoryTransferError.invalidJSON }
                try take(into: &output, limit: limit)
                if escaped == 117 {
                    for _ in 0..<4 {
                        guard let hex = try peek(), (48...57).contains(hex) || (65...70).contains(hex) || (97...102).contains(hex) else {
                            throw HistoryTransferError.invalidJSON
                        }
                        try take(into: &output, limit: limit)
                    }
                } else if ![34, 47, 92, 98, 102, 110, 114, 116].contains(escaped) {
                    throw HistoryTransferError.invalidJSON
                }
            }
        }
        throw HistoryTransferError.invalidJSON
    }

    private func number(into output: inout Data?, limit: Int) throws {
        if try peek() == 45 { try take(into: &output, limit: limit) }
        if try peek() == 48 {
            try take(into: &output, limit: limit)
        } else {
            guard let digit = try peek(), (49...57).contains(digit) else { throw HistoryTransferError.invalidJSON }
            try digits(into: &output, limit: limit)
        }
        if try peek() == 46 {
            try take(into: &output, limit: limit)
            try digits(into: &output, limit: limit, required: true)
        }
        if let byte = try peek(), byte == 69 || byte == 101 {
            try take(into: &output, limit: limit)
            if let sign = try peek(), sign == 43 || sign == 45 { try take(into: &output, limit: limit) }
            try digits(into: &output, limit: limit, required: true)
        }
    }

    private func digits(into output: inout Data?, limit: Int, required: Bool = false) throws {
        var found = false
        while let byte = try peek(), (48...57).contains(byte) {
            found = true
            try take(into: &output, limit: limit)
        }
        if required && !found { throw HistoryTransferError.invalidJSON }
    }

    private func whitespace() throws {
        var output: Data?
        try whitespace(into: &output, limit: 0)
    }

    private func whitespace(into output: inout Data?, limit: Int) throws {
        while let byte = try peek(), [9, 10, 13, 32].contains(byte) { try take(into: &output, limit: limit) }
    }

    private func expect(_ byte: UInt8) throws {
        var output: Data?
        try expect(byte, into: &output, limit: 0)
    }

    private func expect(_ byte: UInt8, into output: inout Data?, limit: Int) throws {
        guard try peek() == byte else { throw HistoryTransferError.invalidJSON }
        try take(into: &output, limit: limit)
    }

    private func take(into output: inout Data?, limit: Int) throws {
        guard let byte = try peek() else { throw HistoryTransferError.invalidJSON }
        if output != nil {
            guard output!.count < limit else { throw HistoryTransferError.resourceLimitExceeded }
            output!.append(byte)
        }
        offset += 1
    }

    private func peek() throws -> UInt8? {
        if offset == buffer.count {
            try Task.checkCancellation()
            buffer = try handle.read(upToCount: 64 * 1024) ?? Data()
            offset = 0
        }
        return buffer.isEmpty ? nil : buffer[offset]
    }
}

/// Actor ownership keeps file scanning and skipped fields away from the UI
/// executor. Each request returns one bounded value, providing backpressure.
actor HistoryJSONArrayReader {
    private let reader: HistoryJSONReader
    private let arrayKey: String
    private var inArray = false
    private var sawArray = false
    private var finished = false
    private var started = false

    init(url: URL, arrayKey: String) throws {
        reader = try HistoryJSONReader(url: url)
        self.arrayKey = arrayKey
    }

    func nextValue() throws -> Data? {
        if finished { return nil }
        if !started {
            try reader.beginObject()
            started = true
        }
        while true {
            if inArray {
                if let value = try reader.nextElement() { return value }
                inArray = false
            }
            guard let key = try reader.nextKey() else {
                try reader.finish()
                guard sawArray else { throw HistoryTransferError.invalidJSON }
                finished = true
                return nil
            }
            if key == arrayKey {
                guard !sawArray else { throw HistoryTransferError.invalidJSON }
                sawArray = true
                inArray = true
                try reader.beginArray()
            } else {
                try reader.skipValue()
            }
        }
    }
}
