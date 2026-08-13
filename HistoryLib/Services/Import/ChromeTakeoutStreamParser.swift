import Foundation

enum ChromeTakeoutStreamError: LocalizedError {
    case missingHistoryArray
    case truncatedJSON

    var errorDescription: String? {
        switch self {
        case .missingHistoryArray:
            return String(localized: "The file does not contain Chrome browser history.")
        case .truncatedJSON:
            return String(localized: "The Chrome browser history file is incomplete or damaged.")
        }
    }
}

struct ChromeTakeoutRecord: Decodable {
    let url: String?
    let title: String?
    let timeUsec: Int64?

    private enum CodingKeys: String, CodingKey {
        case url
        case title
        case timeUsec = "time_usec"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        timeUsec = container.decodeFlexibleInt64IfPresent(forKey: .timeUsec)
    }
}

/// Reads the Takeout history array without retaining the complete JSON document
/// or its full record array in memory. Only one record and one input block are
/// resident at a time.
struct ChromeTakeoutStreamParser {
    private static let readSize = 64 * 1024
    private static let historyKey = Array("\"Browser History\"".utf8)

    func parse(
        url: URL,
        onRecord: (ChromeTakeoutRecord) throws -> Void
    ) async throws -> Int {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var scanner = Scanner()
        while let chunk = try handle.read(upToCount: Self.readSize), !chunk.isEmpty {
            try Task.checkCancellation()
            try scanner.consume(chunk, onRecord: onRecord)
            await Task.yield()
            if scanner.finished {
                return scanner.malformedRecordCount
            }
        }
        try scanner.finish()
        return scanner.malformedRecordCount
    }

    private struct Scanner {
        private var prefix: [UInt8] = []
        private var foundHistoryArray = false
        private var recordBytes: [UInt8] = []
        private var objectDepth = 0
        private var inString = false
        private var escaped = false
        private(set) var malformedRecordCount = 0
        private(set) var finished = false

        mutating func consume(
            _ data: Data,
            onRecord: (ChromeTakeoutRecord) throws -> Void
        ) throws {
            for byte in data {
                if finished { return }
                if !foundHistoryArray {
                    prefix.append(byte)
                    if byte == UInt8(ascii: "["),
                       let arrayStart = Self.historyArrayStart(in: prefix) {
                        foundHistoryArray = true
                        let remainder = prefix.suffix(from: arrayStart + 1)
                        prefix.removeAll(keepingCapacity: false)
                        for remainingByte in remainder {
                            try consumeArrayByte(remainingByte, onRecord: onRecord)
                        }
                    } else if prefix.count > ChromeHistoryImporter.sniffByteLimit {
                        throw ChromeTakeoutStreamError.missingHistoryArray
                    }
                    continue
                }
                try consumeArrayByte(byte, onRecord: onRecord)
            }
        }

        mutating func finish() throws {
            guard foundHistoryArray else {
                throw ChromeTakeoutStreamError.missingHistoryArray
            }
            guard finished, objectDepth == 0, !inString else {
                throw ChromeTakeoutStreamError.truncatedJSON
            }
        }

        private mutating func consumeArrayByte(
            _ byte: UInt8,
            onRecord: (ChromeTakeoutRecord) throws -> Void
        ) throws {
            if objectDepth == 0 {
                if byte == UInt8(ascii: "]") {
                    finished = true
                } else if byte == UInt8(ascii: "{") {
                    objectDepth = 1
                    recordBytes = [byte]
                }
                return
            }

            recordBytes.append(byte)
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                return
            }

            switch byte {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "{"):
                objectDepth += 1
            case UInt8(ascii: "}"):
                objectDepth -= 1
                if objectDepth == 0 {
                    try decodeRecord(onRecord: onRecord)
                    recordBytes.removeAll(keepingCapacity: true)
                }
            default:
                break
            }
        }

        private mutating func decodeRecord(
            onRecord: (ChromeTakeoutRecord) throws -> Void
        ) throws {
            let record: ChromeTakeoutRecord
            do {
                record = try JSONDecoder().decode(ChromeTakeoutRecord.self, from: Data(recordBytes))
            } catch {
                malformedRecordCount += 1
                return
            }
            try onRecord(record)
        }

        private static func historyArrayStart(in bytes: [UInt8]) -> Int? {
            guard bytes.count >= ChromeTakeoutStreamParser.historyKey.count else { return nil }
            let key = ChromeTakeoutStreamParser.historyKey
            let lastStart = bytes.count - key.count
            for start in 0...lastStart where bytes[start..<(start + key.count)].elementsEqual(key) {
                var index = start + key.count
                while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { continue }
                index += 1
                while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }
                if index < bytes.count, bytes[index] == UInt8(ascii: "[") {
                    return index
                }
            }
            return nil
        }

        private static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }
    }
}
