import CoreBluetooth
import CoreLocation
import CryptoKit
import Foundation
import NearbyInteraction
import UIKit
import UserNotifications

/// Bluetooth only: works with Wi-Fi and mobile data off.
/// Every device advertises a Blip service and publishes an L2CAP channel; the device with the lower code
/// connects to the other. Each link agrees a fresh X25519 key and encrypts everything with ChaChaPoly.
/// RSSI gives the radar distance, NearbyInteraction (UWB) the precise one when both phones support it.
final class PeerService: NSObject, ObservableObject {
    static let bleService = CBUUID(string: "6E1A0001-B5A3-4F39-9C4B-2D7E0A1C0B11")
    static let psmCharacteristic = CBUUID(string: "6E1A0002-B5A3-4F39-9C4B-2D7E0A1C0B11")

    private enum Frame: UInt8 { case hello = 0, envelope = 1, media = 2 }

    private struct Hello: Codable {
        let id: String
        let kind: String
        let key: Data
    }

    private struct MediaHeader: Codable {
        let id: UUID
        let viewOnce: Bool
        let kind: MessageKind
    }

    private final class Link {
        let connection: BLEConnection
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        var peerID: String?
        var key: SymmetricKey?
        init(_ connection: BLEConnection) { self.connection = connection }
    }

    @Published private(set) var peers: [String: Peer] = [:]
    @Published private(set) var devices: [UUID: BLEDevice] = [:]
    @Published private(set) var chats: [String: [ChatMessage]] = [:]
    @Published private(set) var bluetoothOff = false
    /// Unread received messages per peer; cleared when that chat is open.
    @Published private(set) var unread: [String: Int] = [:]
    /// The chat on screen right now, so its messages don't notify.
    var activeChat: String? {
        didSet { if let activeChat { markRead(activeChat) } }
    }
    var totalUnread: Int { unread.values.reduce(0, +) }

    let mediaDir: URL
    let location = LocationService()
    private var lastShared: (at: Date, location: CLLocation)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheralManager!
    private var links: [String: Link] = [:]
    private var pendingLinks: [ObjectIdentifier: Link] = [:]
    /// Outgoing connections: peer code → the remote peripheral (kept alive for the channel's lifetime).
    private var remotes: [String: CBPeripheral] = [:]
    /// One token per dial attempt, so a stale timeout or a late disconnect can't cancel a newer attempt.
    private var attempts: [String: UUID] = [:]
    /// Which code each Blip peripheral had. In the background iOS drops the name from adverts,
    /// so this is how a locked phone still recognises (and reconnects to) a known device.
    private var knownCodes: [UUID: String] = [:]

    /// False while the app is in the background, the phone is locked, or (on Mac) another app is in front.
    var appActive = true {
        didSet {
            guard appActive != oldValue else { return }
            rescan()
            if appActive, let activeChat { markRead(activeChat) }
        }
    }
    /// Last time each peer's RSSI was published, to keep UI updates to a few per second.
    private var lastRSSIPublish: [String: Date] = [:]
    private var niSessions: [String: NISession] = [:]
    private var pendingTokens: [String: Data] = [:]
    private var pruneTimer: Timer?

    override init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        mediaDir = caches.appendingPathComponent("media", isDirectory: true)
        // Chats live only in memory, so leftover media from a previous launch is orphaned: wipe it.
        try? FileManager.default.removeItem(at: mediaDir)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        peripheral = CBPeripheralManager(delegate: self, queue: nil)
        location.onUpdate = { [weak self] in self?.shareLocation($0) }
        refreshBadge() // chats don't survive a relaunch, so neither does an old count
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.prune() }
    }

    // MARK: - Sending

    func sendText(_ text: String, to peerID: String) {
        let env = Envelope(kind: .text, text: text)
        let sent = send(env, to: peerID)
        append(ChatMessage(id: env.id, fromMe: true, kind: .text, text: text, status: sent ? .sent : .failed), to: peerID)
    }

    /// The sender keeps no copy: the file is deleted once read into memory.
    func sendMedia(_ url: URL, kind: MessageKind, viewOnce: Bool, to peerID: String) {
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        append(ChatMessage(id: id, fromMe: true, kind: kind, viewOnce: viewOnce, status: .sending), to: peerID)
        guard let link = links[peerID], let key = link.key,
              let file = try? Data(contentsOf: url),
              let header = try? JSONEncoder().encode(MediaHeader(id: id, viewOnce: viewOnce, kind: kind)),
              let sealed = try? ChaChaPoly.seal(Data([UInt8(header.count >> 8), UInt8(header.count & 0xFF)]) + header + file, using: key).combined
        else {
            update(id, in: peerID) { $0.status = .failed }
            return
        }
        link.connection.send(Frame.media.rawValue, sealed,
                             progress: { [weak self] p in
                                 guard let self, let old = self.chats[peerID]?.first(where: { $0.id == id })?.progress,
                                       p - old < 0.01 else {
                                     self?.update(id, in: peerID) { $0.progress = p }
                                     return
                                 }
                             },
                             done: { [weak self] ok in
                                 self?.update(id, in: peerID) {
                                     $0.status = ok ? .sent : .failed
                                     $0.progress = nil
                                 }
                             })
    }

    /// Called when the viewer closes. View-once (or anything we can't keep) is deleted for good.
    func finishedViewing(_ msg: ChatMessage, peerID: String) {
        if msg.viewOnce || !Storage.canKeep {
            if let url = msg.fileURL { try? FileManager.default.removeItem(at: url) }
            update(msg.id, in: peerID) {
                $0.opened = true
                $0.fileURL = nil
            }
        }
        if msg.viewOnce { send(Envelope(kind: .opened, id: msg.id), to: peerID) }
    }

    func react(_ emoji: String, to msg: ChatMessage, peerID: String) {
        let value = msg.reaction == emoji ? nil : emoji
        update(msg.id, in: peerID) { $0.reaction = value }
        send(Envelope(kind: .reaction, id: msg.id, text: value), to: peerID)
    }

    /// Sends the nickname (or an empty one to go anonymous) to everyone connected.
    func broadcastNickname() {
        links.keys.forEach { send(Envelope(kind: .hello, text: Identity.nickname), to: $0) }
    }

    /// Sends our GPS position to everyone connected: at most every 3 s, and only after moving 3 m.
    private func shareLocation(_ loc: CLLocation, to only: String? = nil, force: Bool = false) {
        guard UserDefaults.standard.bool(forKey: Pref.shareLocation) else { return }
        if !force, let last = lastShared, Date().timeIntervalSince(last.at) < 3 || loc.distance(from: last.location) < 3 { return }
        lastShared = (Date(), loc)
        let env = Envelope(kind: .location, lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, alt: loc.altitude)
        (only.map { [$0] } ?? Array(links.keys)).forEach { send(env, to: $0) }
    }

    @discardableResult
    private func send(_ env: Envelope, to peerID: String) -> Bool {
        guard let link = links[peerID], let key = link.key,
              let json = try? JSONEncoder().encode(env),
              let sealed = try? ChaChaPoly.seal(json, using: key).combined else { return false }
        link.connection.send(Frame.envelope.rawValue, sealed)
        return true
    }

    // MARK: - Links

    private func startLink(_ channel: CBL2CAPChannel) {
        let connection = BLEConnection(channel: channel)
        let link = Link(connection)
        pendingLinks[ObjectIdentifier(connection)] = link
        connection.onFrame = { [weak self, weak link] type, payload in
            guard let self, let link else { return }
            self.handle(type, payload, on: link)
        }
        connection.onReceiveProgress = { [weak self, weak link] p in
            guard let self, let id = link?.peerID else { return }
            if let p, let old = self.peers[id]?.incoming, p - old < 0.01 { return }
            self.upsertPeer(id: id) { $0.incoming = p }
        }
        connection.onClose = { [weak self, weak link] in
            guard let self, let link else { return }
            self.linkClosed(link)
        }
        let hello = Hello(id: Identity.shortID, kind: Identity.kind, key: link.privateKey.publicKey.rawRepresentation)
        if let data = try? JSONEncoder().encode(hello) { connection.send(Frame.hello.rawValue, data) }
    }

    private func handle(_ type: UInt8, _ payload: Data, on link: Link) {
        switch Frame(rawValue: type) {
        case .hello:
            guard let hello = try? JSONDecoder().decode(Hello.self, from: payload),
                  let remoteKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: hello.key),
                  let secret = try? link.privateKey.sharedSecretFromKeyAgreement(with: remoteKey) else {
                link.connection.close()
                return
            }
            link.key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("blip-v1".utf8),
                                                      sharedInfo: Data(), outputByteCount: 32)
            link.peerID = hello.id
            pendingLinks.removeValue(forKey: ObjectIdentifier(link.connection))
            if let old = links[hello.id], old !== link { old.connection.close() }
            links[hello.id] = link
            upsertPeer(id: hello.id, kind: hello.kind) { $0.connected = true }
            send(Envelope(kind: .hello, text: Identity.nickname), to: hello.id)
            if let loc = location.location { shareLocation(loc, to: hello.id, force: true) }
            startNI(peer: hello.id)

        case .envelope:
            guard let id = link.peerID, let data = open(payload, with: link),
                  let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
            switch env.kind {
            case .text:
                append(ChatMessage(id: env.id, fromMe: false, kind: .text, text: env.text, status: .received), to: id)
            case .opened:
                update(env.id, in: id) { $0.opened = true }
            case .niToken:
                if let token = env.token { runNI(peer: id, tokenData: token) }
            case .reaction:
                update(env.id, in: id) { $0.reaction = env.text }
            case .delivered:
                update(env.id, in: id) { $0.status = max($0.status, .delivered) }
            case .seen:
                update(env.id, in: id) { $0.status = max($0.status, .seen) }
            case .hello:
                upsertPeer(id: id) { $0.nickname = env.text?.isEmpty == false ? env.text : nil }
            case .location:
                guard let lat = env.lat, let lon = env.lon else { return }
                upsertPeer(id: id) {
                    $0.location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                             altitude: env.alt ?? 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: Date())
                }
            }

        case .media:
            guard let id = link.peerID, let data = open(payload, with: link), data.count > 2 else { return }
            let headerLength = Int(data[data.startIndex]) << 8 | Int(data[data.startIndex + 1])
            let body = data.dropFirst(2)
            guard body.count >= headerLength,
                  let header = try? JSONDecoder().decode(MediaHeader.self, from: body.prefix(headerLength)),
                  header.kind != .text else { return }
            let dest = mediaDir.appendingPathComponent("\(header.id.uuidString).\(header.kind == .photo ? "jpg" : "mp4")")
            guard (try? body.dropFirst(headerLength).write(to: dest)) != nil else { return }
            append(ChatMessage(id: header.id, fromMe: false, kind: header.kind, fileURL: dest, viewOnce: header.viewOnce, status: .received), to: id)

        case nil:
            break
        }
    }

    private func open(_ payload: Data, with link: Link) -> Data? {
        guard let key = link.key, let box = try? ChaChaPoly.SealedBox(combined: payload) else { return nil }
        return try? ChaChaPoly.open(box, using: key)
    }

    private func linkClosed(_ link: Link) {
        pendingLinks.removeValue(forKey: ObjectIdentifier(link.connection))
        guard let id = link.peerID, links[id] === link else { return }
        links.removeValue(forKey: id)
        niSessions.removeValue(forKey: id)?.invalidate()
        pendingTokens.removeValue(forKey: id)
        if let remote = remotes[id] {
            forgetRemote(id)
            central.cancelPeripheralConnection(remote)
            // We are the dialer: queue a reconnect. iOS keeps it pending (even while locked)
            // and completes it as soon as the other device is back in range.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.connectIfNeeded(remote, code: id, patient: true)
            }
        }
        upsertPeer(id: id) {
            $0.connected = false
            $0.incoming = nil
            $0.preciseDistance = nil
            $0.direction = nil
        }
    }

    /// The lower code dials the higher one, so two phones never connect twice.
    /// `patient`: no timeout, used while locked or after a drop so the connection completes whenever possible.
    private func connectIfNeeded(_ remote: CBPeripheral, code: String, patient: Bool = false) {
        guard Identity.shortID < code, links[code] == nil, remotes[code] == nil, central.state == .poweredOn else { return }
        let attempt = UUID()
        remotes[code] = remote
        attempts[code] = attempt
        remote.delegate = self
        central.connect(remote)
        guard !patient else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.links[code] == nil, self.attempts[code] == attempt else { return }
            self.forgetRemote(code)
            self.central.cancelPeripheralConnection(remote)
        }
    }

    private func forgetRemote(_ code: String) {
        remotes.removeValue(forKey: code)
        attempts.removeValue(forKey: code)
    }

    /// In front: scan everything with duplicates (live radar distances, other devices).
    /// In the background: iOS only allows scanning for our own service, which is all that's needed to reconnect.
    private func rescan() {
        guard central.state == .poweredOn else { return }
        central.stopScan()
        if appActive {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        } else {
            central.scanForPeripherals(withServices: [Self.bleService])
        }
    }

    /// Bluetooth went off: CoreBluetooth drops every connection without telling us, so reset everything.
    private func resetConnections() {
        (Array(links.values) + Array(pendingLinks.values)).forEach { $0.connection.close() }
        pendingLinks.removeAll()
        remotes.removeAll()
        attempts.removeAll()
    }

    private func code(for remote: CBPeripheral) -> String? {
        remotes.first { $0.value === remote }?.key
    }

    // MARK: - State helpers (main thread)

    private func upsertPeer(id: String, kind: String? = nil, _ change: (inout Peer) -> Void) {
        guard id != Identity.shortID else { return }
        var peer = peers[id] ?? Peer(id: id, kind: kind ?? "Phone")
        if let kind { peer.kind = kind }
        change(&peer)
        peer.lastSeen = Date()
        peers[id] = peer
    }

    private func append(_ msg: ChatMessage, to peerID: String) {
        chats[peerID, default: []].append(msg)
        guard !msg.fromMe else { return }
        let onScreen = activeChat == peerID && appActive
        guard !onScreen else {
            markRead(peerID)
            return
        }
        send(Envelope(kind: .delivered, id: msg.id), to: peerID)
        unread[peerID, default: 0] += 1
        notify(msg, from: peerID)
    }

    /// The red number on the app icon (iPhone home screen and Mac Dock) = unread messages.
    func refreshBadge() {
        let on = UserDefaults.standard.bool(forKey: Pref.notifyBadge)
        UNUserNotificationCenter.current().setBadgeCount(on ? totalUnread : 0)
    }

    func markRead(_ peerID: String) {
        // Tell them which of their messages we have now seen.
        for i in chats[peerID]?.indices ?? 0..<0 where !chats[peerID]![i].fromMe && !chats[peerID]![i].seenSent {
            chats[peerID]![i].seenSent = true
            send(Envelope(kind: .seen, id: chats[peerID]![i].id), to: peerID)
        }
        unread[peerID] = nil
        refreshBadge()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [peerID])
    }

    /// Local notification only: nothing leaves the device.
    private func notify(_ msg: ChatMessage, from peerID: String) {
        refreshBadge()
        let prefs = UserDefaults.standard
        guard prefs.bool(forKey: Pref.notifyBanner) else { return }
        let content = UNMutableNotificationContent()
        content.title = peers[peerID]?.title ?? "NonNet"
        switch msg.kind {
        case _ where !prefs.bool(forKey: Pref.notifyPreview): content.body = "New message"
        case .text: content.body = msg.text ?? ""
        case .photo: content.body = msg.viewOnce ? "📷 Photo · 1X" : "📷 Photo"
        case .video: content.body = msg.viewOnce ? "🎬 Video · 1X" : "🎬 Video"
        }
        content.sound = prefs.bool(forKey: Pref.notifySound) ? .default : nil
        content.threadIdentifier = peerID
        content.userInfo = ["peer": peerID]
        if prefs.bool(forKey: Pref.notifyBadge) { content.badge = NSNumber(value: totalUnread) }
        // One notification per chat: a newer message replaces the older banner.
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: peerID, content: content, trigger: nil))
    }

    private func update(_ id: UUID, in peerID: String, _ change: (inout ChatMessage) -> Void) {
        guard let i = chats[peerID]?.firstIndex(where: { $0.id == id }) else { return }
        change(&chats[peerID]![i])
    }

    private func prune() {
        let now = Date()
        peers = peers.filter { $0.value.connected || now.timeIntervalSince($0.value.lastSeen) < 10 }
        devices = devices.filter { now.timeIntervalSince($0.value.lastSeen) < 8 }
    }

    // MARK: - Nearby Interaction (UWB)

    private func startNI(peer id: String) {
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else { return }
        let ni = NISession()
        ni.delegate = self
        niSessions[id] = ni
        if let token = ni.discoveryToken,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            send(Envelope(kind: .niToken, token: data), to: id)
        }
        if let pending = pendingTokens.removeValue(forKey: id) { runNI(peer: id, tokenData: pending) }
    }

    private func runNI(peer id: String, tokenData: Data) {
        guard let ni = niSessions[id] else {
            pendingTokens[id] = tokenData
            return
        }
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else { return }
        ni.run(NINearbyPeerConfiguration(peerToken: token))
    }

    // MARK: - Bluetooth helpers

    private static func meters(rssi: Float, txPower: Float?) -> Float {
        let measuredPower = txPower.map { $0 - 41 } ?? -59 // RSSI at 1 m
        return pow(10, (measuredPower - rssi) / (10 * 2.2))
    }

    private static func smooth(_ old: Float?, _ new: Float) -> Float {
        guard let old else { return new }
        return old * 0.7 + new * 0.3
    }

    /// Maker and device type, from the Bluetooth SIG company ID in the manufacturer data.
    /// For Apple, the Continuity message type tells headphones, TV, AirTag and phone/Mac apart.
    private static func identify(from ad: [String: Any]) -> (kind: String, icon: String) {
        guard let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data, m.count >= 2 else {
            return ("Bluetooth", "wave.3.right")
        }
        let bytes = [UInt8](m)
        let company = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        switch company {
        case 0x004C:
            switch bytes.count > 2 ? bytes[2] : 0 {
            case 0x07: return ("Apple · headphones", "airpodspro")
            case 0x09: return ("Apple · TV / HomePod", "appletv")
            case 0x12: return ("Apple · AirTag / Find My", "airtag")
            case 0x02: return ("Beacon", "sensor.tag.radiowaves.forward")
            case 0x0C, 0x0F, 0x10: return ("Apple · phone / Mac", "iphone")
            default: return ("Apple", "applelogo")
            }
        case 0x0006: return ("Microsoft · PC", "pc")
        case 0x0075: return ("Samsung", "smartphone")
        case 0x00E0: return ("Google", "smartphone")
        case 0x012D: return ("Sony", "headphones")
        case 0x0087: return ("Garmin · watch", "applewatch")
        case 0x009E: return ("Bose · headphones", "headphones")
        case 0x027D: return ("Huawei", "smartphone")
        case 0x038F: return ("Xiaomi", "smartphone")
        default: return ("Bluetooth", "wave.3.right")
        }
    }
}

// MARK: - NISessionDelegate

extension PeerService: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let id = niSessions.first(where: { $0.value === session })?.key,
              let obj = nearbyObjects.first else { return }
        upsertPeer(id: id) {
            if let d = obj.distance { $0.preciseDistance = d }
            if let dir = obj.direction { $0.direction = dir }
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let id = niSessions.first(where: { $0.value === session })?.key else { return }
        upsertPeer(id: id) {
            $0.preciseDistance = nil
            $0.direction = nil
        }
        // Peer timed out: run again so UWB resumes when they come back in range.
        if reason == .timeout, let config = session.configuration { session.run(config) }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard let id = niSessions.first(where: { $0.value === session })?.key else { return }
        niSessions.removeValue(forKey: id)
        upsertPeer(id: id) {
            $0.preciseDistance = nil
            $0.direction = nil
        }
    }

    func sessionSuspensionEnded(_ session: NISession) {
        if let config = session.configuration { session.run(config) }
    }
}

// MARK: - Central: scanning, distance, dialing out

extension PeerService: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothOff = central.state != .poweredOn
        guard central.state == .poweredOn else {
            resetConnections()
            return
        }
        rescan()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData ad: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.floatValue
        guard rssi < 0 else { return } // 127 means "unavailable"
        let meters = Self.meters(rssi: rssi, txPower: (ad[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.floatValue)

        let services = ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let named = ad[CBAdvertisementDataLocalNameKey] as? String
        if services.contains(Self.bleService) || knownCodes[peripheral.identifier] != nil,
           let code = (services.contains(Self.bleService) ? named : nil) ?? knownCodes[peripheral.identifier] {
            knownCodes[peripheral.identifier] = code
            connectIfNeeded(peripheral, code: code, patient: !appActive)
            let now = Date()
            if let last = lastRSSIPublish[code], now.timeIntervalSince(last) < 0.2 { return }
            lastRSSIPublish[code] = now
            upsertPeer(id: code) { $0.bleDistance = Self.smooth($0.bleDistance, meters) }
            return
        }

        let now = Date()
        if let existing = devices[peripheral.identifier], now.timeIntervalSince(existing.lastSeen) < 0.25 { return }
        let (kind, icon) = Self.identify(from: ad)
        var device = devices[peripheral.identifier]
            ?? BLEDevice(id: peripheral.identifier, kind: kind, icon: icon, distance: meters, lastSeen: now)
        if let name = ad[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name { device.name = name }
        device.distance = Self.smooth(device.distance, meters)
        device.lastSeen = now
        devices[peripheral.identifier] = device
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.bleService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let code = code(for: peripheral) { forgetRemote(code) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // A channel still waiting for its hello on this connection is dead too.
        for link in pendingLinks.values where link.connection.channel.peer === peripheral { link.connection.close() }
        // A late disconnect from an earlier cancel must not wipe a new attempt already under way.
        guard peripheral.state != .connecting, let code = code(for: peripheral) else { return }
        forgetRemote(code)
        links[code]?.connection.close()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.bleService }) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.psmCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.psmCharacteristic }) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value, value.count >= 2 else { return }
        let psm = CBL2CAPPSM(UInt16(value[value.startIndex]) | UInt16(value[value.startIndex + 1]) << 8)
        peripheral.openL2CAPChannel(psm)
    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard let channel else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        startLink(channel)
    }
}

// MARK: - Peripheral: advertising and accepting channels

extension PeerService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        peripheral.publishL2CAPChannel(withEncryption: false) // Blip encrypts each link itself.
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        guard error == nil else { return }
        // Dialers read the channel number (PSM) from this characteristic.
        let characteristic = CBMutableCharacteristic(type: Self.psmCharacteristic, properties: .read,
                                                     value: Data([UInt8(PSM & 0xFF), UInt8(PSM >> 8)]),
                                                     permissions: .readable)
        let service = CBMutableService(type: Self.bleService, primary: true)
        service.characteristics = [characteristic]
        peripheral.removeAllServices()
        peripheral.add(service)
        // Only the 4-char random code is advertised: it fits the BLE packet and says nothing about the owner.
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.bleService],
            CBAdvertisementDataLocalNameKey: Identity.shortID,
        ])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard let channel else { return }
        startLink(channel)
    }
}
