import Darwin
import Foundation
import simd

final class PoseReceiver {
    private let queue = DispatchQueue(label: "vrb.pose.receiver", qos: .userInitiated)
    private let endpoint: String
    private let decoder = MessagePackDecoder()
    private let lock = NSLock()
    private var latest = PoseFrame.empty
    private var subscriber: ZeroMQSubscriber?
    private var running = false

    init(host: String = ZMQ_HOST, port: UInt16 = ZMQ_PORT) {
        endpoint = "tcp://\(host):\(port)"
    }

    func start() {
        guard !running else { return }
        do {
            let subscriber = try ZeroMQSubscriber(
                endpoint: endpoint,
                subscriptions: ["mp.pose", "yolo.pose", "yolo.seg", "flow.dense", "depth.map", "particle.state"]
            )
            self.subscriber = subscriber
            running = true
            queue.async { [weak self] in
                self?.receiveLoop()
            }
        } catch {
            fputs("PoseReceiver failed to start ZMQ subscriber: \(error)\n", stderr)
        }
    }

    func stop() {
        running = false
        subscriber?.close()
        subscriber = nil
    }

    func latestFrame() -> PoseFrame {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func ingestMessage(topic: String, payload: Data) {
        guard ["mp.pose", "yolo.pose", "yolo.seg", "flow.dense", "depth.map", "particle.state"].contains(topic) else { return }
        guard let root = decodeRootObject(payload) else { return }
        lock.lock()
        var frame = latest
        applyMessage(topic: topic, root: root, frame: &frame)
        latest = frame
        lock.unlock()
    }

    private func receiveLoop() {
        while running, let packet = subscriber?.recv() {
            guard let separator = packet.firstIndex(of: 0x20) else { continue }
            let topicData = packet.prefix(upTo: separator)
            let payload = packet.suffix(from: packet.index(after: separator))
            guard let topic = String(data: topicData, encoding: .utf8) else { continue }
            ingestMessage(topic: topic, payload: Data(payload))
        }
    }

    private func applyMessage(topic: String, root: [String: Any], frame: inout PoseFrame) {
        let frameID = UInt64((root["frame_id"] as? Int64) ?? Int64(frame.frameID))
        let timestamp = root["timestamp"] as? Double ?? frame.timestamp
        let detected = root["detected"] as? Bool ?? frame.detected
        let data = root["data"] as? [String: Any] ?? [:]

        frame.frameID = max(frame.frameID, frameID)
        frame.timestamp = max(frame.timestamp, timestamp)
        frame.source = topic

        switch topic {
        case "mp.pose":
            frame.detected = detected
            frame.landmarks = Self.parseLandmarks(data["landmarks_norm"], jointCount: JOINT_COUNT, width: 4)
            frame.velocities = Self.parseVectors2(data["velocity"], jointCount: JOINT_COUNT)
            frame.speeds = Self.parseSpeeds(data["speed_norm"], fallbackVectors: frame.velocities, jointCount: JOINT_COUNT)
            frame.com = Self.parseVector3(data["com"]) ?? frame.com
        case "yolo.pose":
            let persons = data["persons"] as? [[String: Any]] ?? []
            guard let person = persons.first else {
                frame.detected = detected
                frame.landmarks = Array(repeating: SIMD4<Float>(0, 0, 0, 0), count: JOINT_COUNT)
                frame.velocities = Array(repeating: .zero, count: JOINT_COUNT)
                frame.speeds = Array(repeating: 0, count: JOINT_COUNT)
                return
            }
            frame.detected = detected
            frame.landmarks = Self.parseLandmarks(person["keypoints"], jointCount: JOINT_COUNT, width: 3)
            frame.velocities = Self.parseVectors2(person["velocity"], jointCount: JOINT_COUNT)
            frame.speeds = Self.parseSpeeds(person["speed"], fallbackVectors: frame.velocities, jointCount: JOINT_COUNT)
            frame.com = Self.parseVector3(person["com"]) ?? frame.com
        case "yolo.seg":
            let segments = data["segments"] as? [[String: Any]] ?? []
            if let segment = segments.first {
                let parsed = Self.parsePoints2(segment["polygon"], count: MAX_SEGMENT_POINTS, fallback: frame.segmentPoints)
                frame.segmentCount = parsed.count
                frame.segmentPoints = parsed.points
            }
        case "flow.dense":
            let energy = Self.asFloat(data["energy"])
            let direction = Self.asFloat(data["direction"])
            let quadrants = data["quadrants"] as? [String: Any] ?? [:]
            frame.flowEnergy = energy
            frame.flowVector = SIMD2<Float>(cos(direction) * energy, sin(direction) * energy)
            frame.quadrants = SIMD4<Float>(
                Self.asFloat(quadrants["tl"]),
                Self.asFloat(quadrants["tr"]),
                Self.asFloat(quadrants["bl"]),
                Self.asFloat(quadrants["br"])
            )
        case "depth.map":
            frame.depth = Self.asFloat(data["com_depth"])
            frame.depthMean = Self.asFloat(data["mean"])
        case "particle.state":
            let parsed = Self.parsePoints2(data["spawn_points"], count: MAX_PARTICLE_POINTS, fallback: frame.particlePoints)
            frame.particleCount = parsed.count
            frame.particlePoints = parsed.points
        default:
            break
        }
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

    private static func parsePoints2(_ value: Any?, count: Int, fallback: [SIMD2<Float>]) -> (points: [SIMD2<Float>], count: Int) {
        guard let rows = value as? [[Any]] else {
            return (fallback, 0)
        }
        var result = Array(repeating: SIMD2<Float>(0.5, 0.5), count: count)
        let parsedCount = min(rows.count, count)
        for (index, row) in rows.prefix(count).enumerated() {
            result[index] = SIMD2<Float>(asFloat(row[safe: 0]), asFloat(row[safe: 1]))
        }
        return (result, parsedCount)
    }

    private func decodeRootObject(_ payload: Data) -> [String: Any]? {
        if let root = try? decoder.decode(payload) as? [String: Any] {
            return root
        }
        return Self.parsePythonFallbackObject(payload)
    }

    private static func parsePythonFallbackObject(_ payload: Data) -> [String: Any]? {
        guard var text = String(data: payload, encoding: .utf8) else { return nil }
        guard text.first == "{", text.last == "}" else { return nil }

        text = text.replacingOccurrences(of: "True", with: "true")
        text = text.replacingOccurrences(of: "False", with: "false")
        text = text.replacingOccurrences(of: "None", with: "null")
        text = text.replacingOccurrences(of: "'", with: "\"")

        guard let jsonData = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            return nil
        }
        return object
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

private final class ZeroMQSubscriber {
    private let api: ZeroMQAPI
    private let context: OpaquePointer
    private let socket: OpaquePointer
    private var isClosed = false

    init(endpoint: String, subscriptions: [String]) throws {
        api = try ZeroMQAPI.load()
        guard let context = api.ctxNew() else {
            throw ZeroMQRuntimeError.contextCreationFailed
        }
        self.context = context

        guard let socket = api.socket(context, ZeroMQConstants.subscriber) else {
            _ = api.ctxTerm(context)
            throw ZeroMQRuntimeError.socketCreationFailed
        }
        self.socket = socket

        do {
            try setInt32Option(ZeroMQConstants.linger, value: 0)
            for subscription in subscriptions {
                try setStringOption(ZeroMQConstants.subscribe, value: subscription)
            }
            try call(api.connect(socket, endpoint))
        } catch {
            close()
            throw error
        }
    }

    func recv() -> Data? {
        guard !isClosed else { return nil }

        var storage = Data(count: 64 * 1024)
        let received = storage.withUnsafeMutableBytes { rawBuffer -> Int32 in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return api.recv(socket, baseAddress, Int32(rawBuffer.count), 0)
        }

        if received > 0 {
            storage.count = Int(received)
            return storage
        }

        return nil
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        _ = api.close(socket)
        _ = api.ctxTerm(context)
    }

    deinit {
        close()
    }

    private func setStringOption(_ option: Int32, value: String) throws {
        try value.withCString { cString in
            let length = strlen(cString)
            try call(api.setsockopt(socket, option, cString, length))
        }
    }

    private func setInt32Option(_ option: Int32, value: Int32) throws {
        var mutableValue = value
        try withUnsafePointer(to: &mutableValue) { pointer in
            try call(api.setsockopt(socket, option, pointer, MemoryLayout<Int32>.size))
        }
    }

    private func call(_ result: Int32) throws {
        if result == -1 {
            throw ZeroMQRuntimeError.operationFailed
        }
    }
}

private struct ZeroMQAPI {
    typealias CtxNew = @convention(c) () -> OpaquePointer?
    typealias CtxTerm = @convention(c) (OpaquePointer?) -> Int32
    typealias SocketFn = @convention(c) (OpaquePointer?, Int32) -> OpaquePointer?
    typealias ConnectFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias SetSockOptFn = @convention(c) (OpaquePointer?, Int32, UnsafeRawPointer?, Int) -> Int32
    typealias RecvFn = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, Int32, Int32) -> Int32
    typealias CloseFn = @convention(c) (OpaquePointer?) -> Int32

    let handle: UnsafeMutableRawPointer
    let ctxNew: CtxNew
    let ctxTerm: CtxTerm
    let socket: SocketFn
    let connect: ConnectFn
    let setsockopt: SetSockOptFn
    let recv: RecvFn
    let close: CloseFn

    static func load() throws -> ZeroMQAPI {
        for candidate in ZeroMQConstants.libraryCandidates {
            if let handle = dlopen(candidate, RTLD_NOW) {
                do {
                    return try ZeroMQAPI(handle: handle)
                } catch {
                    dlclose(handle)
                    throw error
                }
            }
        }
        throw ZeroMQRuntimeError.libraryNotFound
    }

    private init(handle: UnsafeMutableRawPointer) throws {
        self.handle = handle
        ctxNew = try Self.resolve("zmq_ctx_new", in: handle)
        ctxTerm = try Self.resolve("zmq_ctx_term", in: handle)
        socket = try Self.resolve("zmq_socket", in: handle)
        connect = try Self.resolve("zmq_connect", in: handle)
        setsockopt = try Self.resolve("zmq_setsockopt", in: handle)
        recv = try Self.resolve("zmq_recv", in: handle)
        close = try Self.resolve("zmq_close", in: handle)
    }

    private static func resolve<T>(_ symbol: String, in handle: UnsafeMutableRawPointer) throws -> T {
        guard let resolved = dlsym(handle, symbol) else {
            throw ZeroMQRuntimeError.symbolMissing(symbol)
        }
        return unsafeBitCast(resolved, to: T.self)
    }
}

private enum ZeroMQConstants {
    static let subscriber: Int32 = 2
    static let linger: Int32 = 17
    static let subscribe: Int32 = 6
    static let libraryCandidates = [
        "libzmq.dylib",
        "/opt/homebrew/lib/libzmq.dylib",
        "/usr/local/lib/libzmq.dylib"
    ]
}

private enum ZeroMQRuntimeError: Error {
    case libraryNotFound
    case symbolMissing(String)
    case contextCreationFailed
    case socketCreationFailed
    case operationFailed
}

extension ZeroMQRuntimeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .libraryNotFound:
            return "libzmq.dylib was not found in the expected runtime locations."
        case let .symbolMissing(symbol):
            return "Missing libzmq symbol: \(symbol)"
        case .contextCreationFailed:
            return "Unable to create ZeroMQ context."
        case .socketCreationFailed:
            return "Unable to create ZeroMQ subscriber socket."
        case .operationFailed:
            return "A ZeroMQ socket operation failed."
        }
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

    private mutating func readArray(count: Int) throws -> [Any] {
        var result: [Any] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(try readValue())
        }
        return result
    }

    private mutating func readMap(count: Int) throws -> [String: Any] {
        var result: [String: Any] = [:]
        result.reserveCapacity(count)
        for _ in 0..<count {
            let keyValue = try readValue()
            guard let key = keyValue as? String else {
                throw MessagePackError.invalidUTF8
            }
            result[key] = try readValue()
        }
        return result
    }

    private mutating func readString(length: Int) throws -> String {
        let subdata = try readData(length: length)
        guard let string = String(data: subdata, encoding: .utf8) else {
            throw MessagePackError.invalidUTF8
        }
        return string
    }

    private mutating func readFloat32() throws -> Float {
        Float(bitPattern: try readUInt32())
    }

    private mutating func readFloat64() throws -> Double {
        Double(bitPattern: try readUInt64())
    }

    private mutating func readUInt16() throws -> UInt16 {
        let data = try readData(length: 2)
        return data.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
    }

    private mutating func readUInt32() throws -> UInt32 {
        let data = try readData(length: 4)
        return data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    private mutating func readUInt64() throws -> UInt64 {
        let data = try readData(length: 8)
        return data.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
    }

    private mutating func readInt8() throws -> Int8 {
        Int8(bitPattern: try readByte())
    }

    private mutating func readInt16() throws -> Int16 {
        Int16(bitPattern: try readUInt16())
    }

    private mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    private mutating func readInt64() throws -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    private mutating func readByte() throws -> UInt8 {
        guard index < data.endIndex else {
            throw MessagePackError.insufficientData
        }
        let byte = data[index]
        index = data.index(after: index)
        return byte
    }

    private mutating func readData(length: Int) throws -> Data {
        guard data.distance(from: index, to: data.endIndex) >= length else {
            throw MessagePackError.insufficientData
        }
        let end = data.index(index, offsetBy: length)
        let subdata = data[index..<end]
        index = end
        return Data(subdata)
    }
}
