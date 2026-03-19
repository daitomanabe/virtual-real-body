import Foundation
import Network
import simd

final class PoseReceiver {
    private let queue = DispatchQueue(label: "vrb.pose.receiver")
    private var connection: NWConnection?
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let decoder = MessagePackDecoder()
    private var buffer = Data()
    private let lock = NSLock()
    private var latest = PoseFrame.empty

    init(host: String = ZMQ_HOST, port: UInt16 = ZMQ_PORT) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? 5555
    }

    func start() {
        guard connection == nil else { return }
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { _ in }
        connection.start(queue: queue)
        receiveNextChunk()
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }

    func latestFrame() -> PoseFrame {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func ingestMessage(topic: String, payload: Data) {
        guard topic == "mp.pose" || topic == "yolo.pose" else { return }
        guard let frame = decodePoseFrame(topic: topic, payload: payload) else { return }
        lock.lock()
        latest = frame
        lock.unlock()
    }

    private func receiveNextChunk() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, _ in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.processBufferedMessages()
            }
            if !complete {
                self.receiveNextChunk()
            }
        }
    }

    private func processBufferedMessages() {
        while let separator = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: separator)
            buffer.removeSubrange(...separator)
            guard let space = line.firstIndex(of: 0x20) else { continue }
            let topicData = line.prefix(upTo: space)
            let payload = line.suffix(from: line.index(after: space))
            guard let topic = String(data: topicData, encoding: .utf8) else { continue }
            ingestMessage(topic: topic, payload: Data(payload))
        }
    }

    private func decodePoseFrame(topic: String, payload: Data) -> PoseFrame? {
        guard let root = try? decoder.decode(payload) as? [String: Any] else {
            return nil
        }

        let frameID = UInt64((root["frame_id"] as? Int64) ?? 0)
        let timestamp = root["timestamp"] as? Double ?? 0
        let detected = root["detected"] as? Bool ?? false
        let data = root["data"] as? [String: Any] ?? [:]

        if topic == "mp.pose" {
            let landmarks = Self.parseLandmarks(data["landmarks_norm"], jointCount: JOINT_COUNT, width: 4)
            let velocities = Self.parseVectors2(data["velocity"], jointCount: JOINT_COUNT)
            let speeds = Self.parseSpeeds(data["speed_norm"], fallbackVectors: velocities, jointCount: JOINT_COUNT)
            let com = Self.parseVector3(data["com"]) ?? SIMD3<Float>(0.5, 0.5, 0)
            return PoseFrame(
                source: topic,
                frameID: frameID,
                timestamp: timestamp,
                detected: detected,
                landmarks: landmarks,
                velocities: velocities,
                speeds: speeds,
                com: com
            )
        }

        let persons = data["persons"] as? [[String: Any]] ?? []
        guard let person = persons.first else { return PoseFrame.empty }
        let landmarks = Self.parseLandmarks(person["keypoints"], jointCount: JOINT_COUNT, width: 3)
        let velocities = Self.parseVectors2(person["velocity"], jointCount: JOINT_COUNT)
        let speeds = Self.parseSpeeds(person["speed"], fallbackVectors: velocities, jointCount: JOINT_COUNT)
        let com = Self.parseVector3(person["com"]) ?? SIMD3<Float>(0.5, 0.5, 0)
        return PoseFrame(
            source: topic,
            frameID: frameID,
            timestamp: timestamp,
            detected: detected,
            landmarks: landmarks,
            velocities: velocities,
            speeds: speeds,
            com: com
        )
    }

    private static func parseLandmarks(_ value: Any?, jointCount: Int, width: Int) -> [SIMD4<Float>] {
        guard let rows = value as? [[Any]] else {
            return Array(repeating: SIMD4<Float>(0, 0, 0, 0), count: jointCount)
        }
        var result = Array(repeating: SIMD4<Float>(0, 0, 0, 0), count: jointCount)
        for (index, row) in rows.prefix(jointCount).enumerated() {
            let x = asFloat(row[safe: 0])
            let y = asFloat(row[safe: 1])
            let z = width > 2 ? asFloat(row[safe: 2]) : 0
            let w = width > 3 ? asFloat(row[safe: 3]) : asFloat(row[safe: 2])
            result[index] = SIMD4<Float>(x, y, z, w)
        }
        return result
    }

    private static func parseVectors2(_ value: Any?, jointCount: Int) -> [SIMD2<Float>] {
        guard let rows = value as? [[Any]] else {
            return Array(repeating: .zero, count: jointCount)
        }
        var result = Array(repeating: SIMD2<Float>.zero, count: jointCount)
        for (index, row) in rows.prefix(jointCount).enumerated() {
            result[index] = SIMD2<Float>(asFloat(row[safe: 0]), asFloat(row[safe: 1]))
        }
        return result
    }

    private static func parseSpeeds(_ value: Any?, fallbackVectors: [SIMD2<Float>], jointCount: Int) -> [Float] {
        if let scalar = value as? Double {
            return Array(repeating: Float(scalar), count: jointCount)
        }
        if let list = value as? [Any] {
            var result = Array(repeating: Float.zero, count: jointCount)
            for (index, item) in list.prefix(jointCount).enumerated() {
                result[index] = asFloat(item)
            }
            return result
        }
        return fallbackVectors.map { simd_length($0) }
    }

    private static func parseVector3(_ value: Any?) -> SIMD3<Float>? {
        guard let row = value as? [Any] else { return nil }
        return SIMD3<Float>(asFloat(row[safe: 0]), asFloat(row[safe: 1]), asFloat(row[safe: 2]))
    }
}

private extension PoseReceiver {
    static func asFloat(_ value: Any?) -> Float {
        switch value {
        case let number as Double:
            return Float(number)
        case let number as Float:
            return number
        case let number as Int:
            return Float(number)
        case let number as Int64:
            return Float(number)
        case let number as UInt64:
            return Float(number)
        default:
            return 0
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum MessagePackError: Error {
    case insufficientData
    case unsupported(UInt8)
    case invalidUTF8
}

struct MessagePackDecoder {
    func decode(_ data: Data) throws -> Any {
        var reader = MessagePackReader(data: data)
        return try reader.readValue()
    }
}

private struct MessagePackReader {
    let data: Data
    var index: Data.Index

    init(data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    mutating func readValue() throws -> Any {
        let marker = try readByte()
        switch marker {
        case 0x00...0x7f:
            return Int64(marker)
        case 0x80...0x8f:
            return try readMap(count: Int(marker & 0x0f))
        case 0x90...0x9f:
            return try readArray(count: Int(marker & 0x0f))
        case 0xa0...0xbf:
            return try readString(length: Int(marker & 0x1f))
        case 0xc0:
            return NSNull()
        case 0xc2:
            return false
        case 0xc3:
            return true
        case 0xca:
            return try readFloat32()
        case 0xcb:
            return try readFloat64()
        case 0xcc:
            return Int64(try readByte())
        case 0xcd:
            return Int64(try readUInt16())
        case 0xce:
            return Int64(try readUInt32())
        case 0xcf:
            return Int64(bitPattern: try readUInt64())
        case 0xd0:
            return Int64(try readInt8())
        case 0xd1:
            return Int64(try readInt16())
        case 0xd2:
            return Int64(try readInt32())
        case 0xd3:
            return try readInt64()
        case 0xd9:
            return try readString(length: Int(try readByte()))
        case 0xda:
            return try readString(length: Int(try readUInt16()))
        case 0xdb:
            return try readString(length: Int(try readUInt32()))
        case 0xdc:
            return try readArray(count: Int(try readUInt16()))
        case 0xdd:
            return try readArray(count: Int(try readUInt32()))
        case 0xde:
            return try readMap(count: Int(try readUInt16()))
        case 0xdf:
            return try readMap(count: Int(try readUInt32()))
        case 0xe0...0xff:
            return Int64(Int8(bitPattern: marker))
        default:
            throw MessagePackError.unsupported(marker)
        }
    }

    mutating func readMap(count: Int) throws -> [String: Any] {
        var result: [String: Any] = [:]
        result.reserveCapacity(count)
        for _ in 0..<count {
            guard let key = try readValue() as? String else {
                throw MessagePackError.invalidUTF8
            }
            result[key] = try readValue()
        }
        return result
    }

    mutating func readArray(count: Int) throws -> [Any] {
        var result: [Any] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(try readValue())
        }
        return result
    }

    mutating func readString(length: Int) throws -> String {
        let bytes = try readBytes(count: length)
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw MessagePackError.invalidUTF8
        }
        return string
    }

    mutating func readFloat32() throws -> Float {
        Float(bitPattern: try readUInt32())
    }

    mutating func readFloat64() throws -> Double {
        Double(bitPattern: try readUInt64())
    }

    mutating func readInt8() throws -> Int8 {
        Int8(bitPattern: try readByte())
    }

    mutating func readInt16() throws -> Int16 {
        Int16(bitPattern: try readUInt16())
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readInt64() throws -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    mutating func readUInt16() throws -> UInt16 {
        let data = try readBytes(count: 2)
        return data.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
    }

    mutating func readUInt32() throws -> UInt32 {
        let data = try readBytes(count: 4)
        return data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    mutating func readUInt64() throws -> UInt64 {
        let data = try readBytes(count: 8)
        return data.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
    }

    mutating func readByte() throws -> UInt8 {
        guard index < data.endIndex else { throw MessagePackError.insufficientData }
        let value = data[index]
        index = data.index(after: index)
        return value
    }

    mutating func readBytes(count: Int) throws -> Data {
        let end = data.index(index, offsetBy: count, limitedBy: data.endIndex)
        guard let end else { throw MessagePackError.insufficientData }
        let slice = data[index..<end]
        index = end
        return Data(slice)
    }
}
