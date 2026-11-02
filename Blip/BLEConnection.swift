import CoreBluetooth
import Foundation

/// One Bluetooth L2CAP channel to another Blip device, framed as [type: 1 byte][length: 4 bytes][payload].
/// Streams run on the main run loop, so every callback arrives on the main thread.
final class BLEConnection: NSObject, StreamDelegate {
    private struct Outgoing {
        let data: Data
        var sent = 0
        let progress: ((Double) -> Void)?
        let done: ((Bool) -> Void)?
    }

    static let maxFrame = 20_000_000
    /// Frames bigger than this report receive progress (videos, not text).
    private static let progressThreshold = 50_000

    let channel: CBL2CAPChannel
    var onFrame: ((UInt8, Data) -> Void)?
    var onReceiveProgress: ((Double?) -> Void)?
    var onClose: (() -> Void)?

    private var inbox = Data()
    private var outbox: [Outgoing] = []
    private var closed = false

    init(channel: CBL2CAPChannel) {
        self.channel = channel
        super.init()
        for stream in [channel.inputStream as Stream?, channel.outputStream as Stream?].compactMap({ $0 }) {
            stream.delegate = self
            stream.schedule(in: .main, forMode: .default)
            stream.open()
        }
    }

    func send(_ type: UInt8, _ payload: Data, progress: ((Double) -> Void)? = nil, done: ((Bool) -> Void)? = nil) {
        guard !closed else {
            done?(false)
            return
        }
        var frame = Data([type])
        var length = UInt32(payload.count).bigEndian
        frame.append(Data(bytes: &length, count: 4))
        frame.append(payload)
        outbox.append(Outgoing(data: frame, progress: progress, done: done))
        pump()
    }

    func close() {
        guard !closed else { return }
        closed = true
        for stream in [channel.inputStream as Stream?, channel.outputStream as Stream?].compactMap({ $0 }) {
            stream.close()
            stream.remove(from: .main, forMode: .default)
        }
        outbox.forEach { $0.done?(false) }
        outbox.removeAll()
        onClose?()
    }

    func stream(_ stream: Stream, handle event: Stream.Event) {
        switch event {
        case .hasBytesAvailable: read()
        case .hasSpaceAvailable: pump()
        case .errorOccurred, .endEncountered: close()
        default: break
        }
    }

    private func pump() {
        guard let output = channel.outputStream else { return }
        while !outbox.isEmpty, output.hasSpaceAvailable {
            var item = outbox[0]
            let written = item.data.withUnsafeBytes { raw -> Int in
                let base = raw.bindMemory(to: UInt8.self).baseAddress! + item.sent
                return output.write(base, maxLength: min(item.data.count - item.sent, 8192))
            }
            if written < 0 {
                close()
                return
            }
            guard written > 0 else { break }
            item.sent += written
            item.progress?(Double(item.sent) / Double(item.data.count))
            if item.sent == item.data.count {
                outbox.removeFirst()
                item.done?(true)
            } else {
                outbox[0] = item
            }
        }
    }

    private func read() {
        guard let input = channel.inputStream else { return }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while input.hasBytesAvailable {
            let count = input.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            inbox.append(buffer, count: count)
        }
        parse()
    }

    private func parse() {
        while !closed, inbox.count >= 5 {
            let length = inbox.subdata(in: 1..<5).reduce(0) { $0 << 8 | Int($1) }
            guard length <= Self.maxFrame else {
                close()
                return
            }
            guard inbox.count >= 5 + length else {
                if length > Self.progressThreshold { onReceiveProgress?(Double(inbox.count - 5) / Double(length)) }
                return
            }
            let type = inbox[0]
            let payload = inbox.subdata(in: 5..<(5 + length))
            inbox = Data(inbox.dropFirst(5 + length))
            if length > Self.progressThreshold { onReceiveProgress?(nil) }
            onFrame?(type, payload)
        }
    }
}
