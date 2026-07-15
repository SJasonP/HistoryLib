import Foundation
import Sodium

enum HistoryLibEncryptedArchiveError: LocalizedError {
    case passwordRequired
    case unsupportedFormat
    case invalidParameters
    case authenticationFailed
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return String(localized: "This HistoryLib archive is password protected.")
        case .unsupportedFormat:
            return String(localized: "Unsupported encrypted HistoryLib archive format.")
        case .invalidParameters:
            return String(localized: "Invalid encrypted HistoryLib archive parameters.")
        case .authenticationFailed:
            return String(localized: "The password is incorrect or the archive is damaged.")
        case .encryptionFailed:
            return String(localized: "Failed to encrypt the HistoryLib archive.")
        }
    }
}

enum HistoryLibEncryptedArchive {
    static let chunkSize = 1_048_576
    static let weakPasswordLength = 12

    private static let magic = Data([0x48, 0x4C, 0x5A, 0x45, 0x4E, 0x43, 0x00, 0x01])
    private static let kdfID: UInt8 = 1
    private static let cipherID: UInt8 = 1
    private static let opsLimit = 2
    private static let memLimit = 67_108_864
    private static let saltSize = 16
    private static let streamHeaderSize = 24
    private static let fixedHeaderSize = 66
    private static let authenticationOverhead = 17

    static func normalizedPassword(_ password: String) -> String {
        password.precomposedStringWithCanonicalMapping
    }

    static func isEncryptedArchive(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: magic.count) else { return false }
        return prefix == magic
    }

    static func encrypt(
        sourceURL: URL,
        destinationURL: URL,
        password: String,
        progress: ((Double) -> Void)? = nil
    ) throws {
        let normalizedPassword = normalizedPassword(password)
        guard !normalizedPassword.isEmpty else {
            throw HistoryLibEncryptedArchiveError.passwordRequired
        }

        let sodium = Sodium()
        guard let salt = sodium.randomBytes.buf(length: saltSize) else {
            throw HistoryLibEncryptedArchiveError.encryptionFailed
        }
        var passwordBytes = Array(normalizedPassword.utf8)
        defer { wipe(&passwordBytes) }
        guard var key = sodium.pwHash.hash(
            outputLength: SecretStream.XChaCha20Poly1305.KeyBytes,
            passwd: passwordBytes,
            salt: salt,
            opsLimit: opsLimit,
            memLimit: memLimit,
            alg: .Argon2ID13
        ) else {
            throw HistoryLibEncryptedArchiveError.encryptionFailed
        }
        defer { wipe(&key) }
        guard let stream = sodium.secretStream.xchacha20poly1305.initPush(secretKey: key) else {
            throw HistoryLibEncryptedArchiveError.encryptionFailed
        }

        let header = makeHeader(salt: salt, streamHeader: stream.header())
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        fileManager.createFile(atPath: destinationURL.path, contents: nil)
        HistoryLibSensitiveFiles.applyAttributes(to: destinationURL)

        do {
            let input = try FileHandle(forReadingFrom: sourceURL)
            let output = try FileHandle(forWritingTo: destinationURL)
            defer {
                try? input.close()
                try? output.close()
            }
            try output.write(contentsOf: header)

            let sourceSize = (try? fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            var processed: Int64 = 0
            var current = try input.read(upToCount: chunkSize) ?? Data()

            if current.isEmpty {
                try writeEncryptedFrame(
                    stream.push(message: [], tag: .FINAL, ad: Array(header)),
                    to: output
                )
            } else {
                while true {
                    try Task.checkCancellation()
                    let next = try input.read(upToCount: chunkSize) ?? Data()
                    let isFinal = next.isEmpty
                    try writeEncryptedFrame(
                        stream.push(
                            message: Array(current),
                            tag: isFinal ? .FINAL : .MESSAGE,
                            ad: Array(header)
                        ),
                        to: output
                    )
                    processed += Int64(current.count)
                    if sourceSize > 0 {
                        progress?(min(Double(processed) / Double(sourceSize), 1))
                    }
                    if isFinal { break }
                    current = next
                }
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    static func decrypt(
        sourceURL: URL,
        destinationURL: URL,
        password: String,
        progress: ((Double) -> Void)? = nil
    ) throws {
        let normalizedPassword = normalizedPassword(password)
        guard !normalizedPassword.isEmpty else {
            throw HistoryLibEncryptedArchiveError.passwordRequired
        }

        let fileManager = FileManager.default
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        let headerData = try readExactly(fixedHeaderSize, from: input)
        let header = try parseHeader(headerData)

        let sodium = Sodium()
        var passwordBytes = Array(normalizedPassword.utf8)
        defer { wipe(&passwordBytes) }
        guard var key = sodium.pwHash.hash(
            outputLength: SecretStream.XChaCha20Poly1305.KeyBytes,
            passwd: passwordBytes,
            salt: header.salt,
            opsLimit: header.opsLimit,
            memLimit: header.memLimit,
            alg: .Argon2ID13
        ) else {
            throw HistoryLibEncryptedArchiveError.authenticationFailed
        }
        defer { wipe(&key) }
        guard let stream = sodium.secretStream.xchacha20poly1305.initPull(
            secretKey: key,
            header: header.streamHeader
        ) else {
            throw HistoryLibEncryptedArchiveError.authenticationFailed
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        fileManager.createFile(atPath: destinationURL.path, contents: nil)
        HistoryLibSensitiveFiles.applyAttributes(to: destinationURL)

        do {
            let output = try FileHandle(forWritingTo: destinationURL)
            defer { try? output.close() }
            let sourceSize = (try? fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            var processed = Int64(fixedHeaderSize)
            var sawFinal = false

            while !sawFinal {
                try Task.checkCancellation()
                let lengthData = try readExactly(4, from: input)
                processed += 4
                let frameLength = Int(try decodeUInt32(lengthData))
                guard frameLength >= authenticationOverhead,
                      frameLength <= header.chunkSize + authenticationOverhead else {
                    throw HistoryLibEncryptedArchiveError.authenticationFailed
                }
                let cipherText = try readExactly(frameLength, from: input)
                processed += Int64(frameLength)
                guard let (message, tag) = stream.pull(
                    cipherText: Array(cipherText),
                    ad: Array(headerData)
                ) else {
                    throw HistoryLibEncryptedArchiveError.authenticationFailed
                }

                switch tag {
                case .MESSAGE:
                    try output.write(contentsOf: Data(message))
                case .FINAL:
                    try output.write(contentsOf: Data(message))
                    sawFinal = true
                case .PUSH, .REKEY:
                    throw HistoryLibEncryptedArchiveError.authenticationFailed
                }
                if sourceSize > 0 {
                    progress?(min(Double(processed) / Double(sourceSize), 1))
                }
            }

            guard (try input.read(upToCount: 1) ?? Data()).isEmpty else {
                throw HistoryLibEncryptedArchiveError.authenticationFailed
            }
        } catch is CancellationError {
            try? fileManager.removeItem(at: destinationURL)
            throw CancellationError()
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if error is HistoryLibEncryptedArchiveError {
                throw error
            }
            throw HistoryLibEncryptedArchiveError.authenticationFailed
        }
    }

    private struct Header {
        let opsLimit: Int
        let memLimit: Int
        let chunkSize: Int
        let salt: [UInt8]
        let streamHeader: [UInt8]
    }

    private static func makeHeader(salt: [UInt8], streamHeader: [UInt8]) -> Data {
        var data = magic
        data.append(kdfID)
        data.append(cipherID)
        appendUInt32(UInt32(opsLimit), to: &data)
        appendUInt64(UInt64(memLimit), to: &data)
        appendUInt32(UInt32(chunkSize), to: &data)
        data.append(contentsOf: salt)
        data.append(contentsOf: streamHeader)
        return data
    }

    private static func parseHeader(_ data: Data) throws -> Header {
        guard data.count == fixedHeaderSize,
              data.prefix(magic.count) == magic,
              data[8] == kdfID,
              data[9] == cipherID else {
            throw HistoryLibEncryptedArchiveError.unsupportedFormat
        }
        let encodedOps = try decodeUInt32(data.subdata(in: 10..<14))
        let encodedMemory = try decodeUInt64(data.subdata(in: 14..<22))
        let encodedChunk = try decodeUInt32(data.subdata(in: 22..<26))
        guard (2...4).contains(encodedOps),
              (67_108_864...268_435_456).contains(encodedMemory),
              (65_536...4_194_304).contains(encodedChunk) else {
            throw HistoryLibEncryptedArchiveError.invalidParameters
        }
        return Header(
            opsLimit: Int(encodedOps),
            memLimit: Int(encodedMemory),
            chunkSize: Int(encodedChunk),
            salt: Array(data[26..<42]),
            streamHeader: Array(data[42..<66])
        )
    }

    private static func writeEncryptedFrame(_ frame: [UInt8]?, to output: FileHandle) throws {
        guard let frame else { throw HistoryLibEncryptedArchiveError.encryptionFailed }
        var length = Data()
        appendUInt32(UInt32(frame.count), to: &length)
        try output.write(contentsOf: length)
        try output.write(contentsOf: Data(frame))
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else {
                throw HistoryLibEncryptedArchiveError.authenticationFailed
            }
            result.append(chunk)
        }
        return result
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt64(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func decodeUInt32(_ data: Data) throws -> UInt32 {
        guard data.count == 4 else { throw HistoryLibEncryptedArchiveError.authenticationFailed }
        return data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func decodeUInt64(_ data: Data) throws -> UInt64 {
        guard data.count == 8 else { throw HistoryLibEncryptedArchiveError.authenticationFailed }
        return data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    private static func wipe(_ bytes: inout [UInt8]) {
        for index in bytes.indices { bytes[index] = 0 }
        bytes.removeAll(keepingCapacity: false)
    }

}

enum HistoryLibSensitiveFiles {
    static func applyAttributes(to url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
#if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
#endif
    }
}
