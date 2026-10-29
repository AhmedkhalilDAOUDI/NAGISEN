import Foundation
import Compression

/// Minimal, read-only ZIP support for data exports.
///
/// Lose It! ships its archive as a `.zip` of CSV files, and Foundation has no archive API,
/// so the central directory is parsed directly. Only `stored` and `deflate` entries are
/// accepted; anything else (encrypted, zip64, exotic compression) is reported as unreadable
/// instead of being guessed at.
enum ZipArchiveReader {
    struct Entry {
        let name: String
        let data: Data
    }

    enum Failure: Error {
        case notAnArchive
        case unsupported(String)
        case corrupt
    }

    private static let endOfCentralDirectory: UInt32 = 0x0605_4b50
    private static let centralFileHeader: UInt32 = 0x0201_4b50
    private static let localFileHeader: UInt32 = 0x0403_4b50
    private static let maximumEntrySize = 64 * 1024 * 1024

    static func isArchive(_ data: Data) -> Bool {
        data.count >= 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4b
            && (data[data.startIndex + 2] == 0x03 || data[data.startIndex + 2] == 0x05)
            && (data[data.startIndex + 3] == 0x04 || data[data.startIndex + 3] == 0x06)
    }

    static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count > 22 else { throw Failure.notAnArchive }

        // The end-of-central-directory record sits in the last 64 KB (plus comment).
        let searchStart = max(0, bytes.count - 65_557)
        var eocdOffset: Int?
        var index = bytes.count - 22
        while index >= searchStart {
            if readUInt32(bytes, index) == endOfCentralDirectory {
                eocdOffset = index
                break
            }
            index -= 1
        }
        guard let eocd = eocdOffset else { throw Failure.notAnArchive }

        guard let entryCount = readUInt16(bytes, eocd + 10),
              let directoryOffset = readUInt32(bytes, eocd + 16) else { throw Failure.corrupt }
        if entryCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF { throw Failure.unsupported("zip64") }

        var offset = Int(directoryOffset)
        var result: [Entry] = []
        for _ in 0..<Int(entryCount) {
            guard readUInt32(bytes, offset) == centralFileHeader else { throw Failure.corrupt }
            guard let method = readUInt16(bytes, offset + 10),
                  let compressedSize = readUInt32(bytes, offset + 20),
                  let uncompressedSize = readUInt32(bytes, offset + 24),
                  let nameLength = readUInt16(bytes, offset + 28),
                  let extraLength = readUInt16(bytes, offset + 30),
                  let commentLength = readUInt16(bytes, offset + 32),
                  let localOffset = readUInt32(bytes, offset + 42) else { throw Failure.corrupt }

            let nameStart = offset + 46
            let nameEnd = nameStart + Int(nameLength)
            guard nameEnd <= bytes.count else { throw Failure.corrupt }
            let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)

            offset = nameEnd + Int(extraLength) + Int(commentLength)

            guard !name.hasSuffix("/") else { continue }
            guard uncompressedSize <= maximumEntrySize else { throw Failure.unsupported("entry too large: \(name)") }

            let local = Int(localOffset)
            guard readUInt32(bytes, local) == localFileHeader,
                  let localNameLength = readUInt16(bytes, local + 26),
                  let localExtraLength = readUInt16(bytes, local + 28) else { throw Failure.corrupt }
            let dataStart = local + 30 + Int(localNameLength) + Int(localExtraLength)
            let dataEnd = dataStart + Int(compressedSize)
            guard dataStart >= 0, dataEnd <= bytes.count else { throw Failure.corrupt }
            let payload = Data(bytes[dataStart..<dataEnd])

            let contents: Data
            switch method {
            case 0:
                contents = payload
            case 8:
                guard let inflated = inflate(payload, expectedSize: Int(uncompressedSize)) else {
                    throw Failure.corrupt
                }
                contents = inflated
            default:
                throw Failure.unsupported("compression method \(method) for \(name)")
            }
            result.append(Entry(name: name, data: contents))
        }
        return result
    }

    private static func inflate(_ payload: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written: Int = output.withUnsafeMutableBytes { destination in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return payload.withUnsafeBytes { source in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destinationBase, expectedSize,
                                                 sourceBase, payload.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { return nil }
        return output
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
