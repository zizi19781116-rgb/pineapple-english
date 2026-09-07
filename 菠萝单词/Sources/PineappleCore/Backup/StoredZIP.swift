import Foundation

/// Standard ZIP with stored (uncompressed) entries. No shell, extraction paths or third-party dependency.
/// The reader accepts only this bounded format, checks central/local headers and CRC for every entry.
public enum StoredZIP {
    public static let maximumBytes = 256 * 1024 * 1024
    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB88320) }
        }
        return crc ^ 0xFFFFFFFF
    }
    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.count < 128 && !name.contains("/") && !name.contains("\\")
            && name != "." && name != ".." && name.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value < 127 }
    }
    public static func encode(_ entries: [String: Data]) throws -> Data {
        guard !entries.isEmpty, entries.count <= 16,
              entries.values.reduce(0, { $0 + $1.count }) < maximumBytes - 4096,
              entries.keys.allSatisfy(validName) else { throw AppError.invalidData("备份过大或文件名无效。") }
        var output = Data(), central = Data()
        for name in entries.keys.sorted() {
            guard let contents = entries[name] else { continue }
            let filename = Data(name.utf8), checksum = crc32(contents), offset = UInt32(output.count)
            output.appendLE(UInt32(0x04034B50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(0x0800))
            output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(33))
            output.appendLE(checksum); output.appendLE(UInt32(contents.count)); output.appendLE(UInt32(contents.count))
            output.appendLE(UInt16(filename.count)); output.appendLE(UInt16(0)); output.append(filename); output.append(contents)
            central.appendLE(UInt32(0x02014B50)); central.appendLE(UInt16(20)); central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(33))
            central.appendLE(checksum); central.appendLE(UInt32(contents.count)); central.appendLE(UInt32(contents.count))
            central.appendLE(UInt16(filename.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0)); central.appendLE(offset)
            central.append(filename)
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.appendLE(UInt32(0x06054B50)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count)); output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(central.count)); output.appendLE(centralOffset); output.appendLE(UInt16(0))
        return output
    }
    public static func decode(_ data: Data) throws -> [String: Data] {
        guard data.count >= 22, data.count <= maximumBytes else { throw AppError.invalidData("备份为空或超过 256 MB。") }
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ length: Int) throws -> Int {
            guard offset >= 0, length > 0, offset <= bytes.count - length else { throw AppError.invalidData("ZIP 文件被截断。") }
            var value = 0
            for n in 0..<length { value |= Int(bytes[offset + n]) << (n * 8) }
            return value
        }
        func part(_ offset: Int, _ length: Int) throws -> Data {
            guard offset >= 0, length >= 0, offset <= bytes.count, length <= bytes.count - offset else {
                throw AppError.invalidData("ZIP 数据范围错误。")
            }
            return Data(bytes[offset..<(offset + length)])
        }
        let end = data.count - 22
        guard try number(end, 4) == 0x06054B50, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0,
              try number(end + 20, 2) == 0 else { throw AppError.invalidData("请使用菠萝单词导出的完整 ZIP 备份。") }
        let count = try number(end + 10, 2), size = try number(end + 12, 4), start = try number(end + 16, 4)
        guard count > 0, count <= 16, try number(end + 8, 2) == count,
              start <= end, size == end - start else { throw AppError.invalidData("ZIP 目录损坏。") }
        var cursor = start, output: [String: Data] = [:], localEnd = 0
        for _ in 0..<count {
            guard try number(cursor, 4) == 0x02014B50, try number(cursor + 8, 2) == 0x0800,
                  try number(cursor + 10, 2) == 0, try number(cursor + 34, 2) == 0 else { throw AppError.invalidData("备份采用不支持的压缩或加密格式。") }
            let checksum = try number(cursor + 16, 4), compressed = try number(cursor + 20, 4), uncompressed = try number(cursor + 24, 4)
            let nameLength = try number(cursor + 28, 2), extraLength = try number(cursor + 30, 2), commentLength = try number(cursor + 32, 2)
            let local = try number(cursor + 42, 4)
            guard compressed == uncompressed, extraLength == 0, commentLength == 0,
                  let name = String(data: try part(cursor + 46, nameLength), encoding: .utf8), validName(name), output[name] == nil,
                  local == localEnd, local < start else { throw AppError.invalidData("ZIP 有重复条目或无效路径。") }
            guard try number(local, 4) == 0x04034B50, try number(local + 6, 2) == 0x0800, try number(local + 8, 2) == 0,
                  try number(local + 14, 4) == checksum, try number(local + 18, 4) == compressed,
                  try number(local + 22, 4) == uncompressed, try number(local + 26, 2) == nameLength,
                  try number(local + 28, 2) == 0, try part(local + 30, nameLength) == Data(name.utf8)
            else { throw AppError.invalidData("ZIP 文件头与目录不一致。") }
            let contentStart = local + 30 + nameLength
            guard contentStart <= start, uncompressed <= start - contentStart else { throw AppError.invalidData("ZIP 数据越界。") }
            let contents = try part(contentStart, uncompressed)
            guard Int(crc32(contents)) == checksum else { throw AppError.invalidData("备份校验失败，文件可能损坏。") }
            output[name] = contents; localEnd = contentStart + uncompressed
            cursor += 46 + nameLength
        }
        guard cursor == end, localEnd == start else { throw AppError.invalidData("ZIP 包含多余数据。") }
        return output
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        for index in 0..<MemoryLayout<T>.size { append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }
}
