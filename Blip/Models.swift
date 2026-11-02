import CoreLocation
import Foundation
import UIKit
import simd

enum Pref {
    static let maxMeters = "maxMeters"
    static let showAllBLE = "showAllBLE"
    static let showNames = "showNames"
    static let keepMedia = "keepMedia"
    static let minFreeGB = "minFreeGB"
    static let nickname = "nickname"
    static let shareLocation = "shareLocation"
    static let notifyBanner = "notifyBanner"
    static let notifySound = "notifySound"
    static let notifyPreview = "notifyPreview"
    static let notifyBadge = "notifyBadge"
}

/// Anonymous by default: device type + random 4-char code, new on every launch. No IP, no account.
/// The user can add a nickname in Settings; it is sent only to connected Blip devices.
enum Identity {
    static let shortID = String(UUID().uuidString.prefix(4))
    static var kind: String { ProcessInfo.processInfo.isiOSAppOnMac ? "Mac" : UIDevice.current.model }
    static var displayName: String { "\(kind)·\(shortID)" }
    static var nickname: String {
        (UserDefaults.standard.string(forKey: Pref.nickname) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ name: String) -> (kind: String, id: String) {
        let parts = name.components(separatedBy: "·")
        return parts.count == 2 ? (parts[0], parts[1]) : ("Phone", name)
    }

    static func icon(_ kind: String) -> String {
        switch kind {
        case "iPad": "ipad"
        case "Mac": "laptopcomputer"
        default: "iphone"
        }
    }
}

enum Storage {
    static var freeGB: Double {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Double(values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000
    }

    /// Received photos and videos (not view-once) are kept only if the user wants it and there is enough free space.
    static var canKeep: Bool {
        let d = UserDefaults.standard
        return d.bool(forKey: Pref.keepMedia) && freeGB >= d.double(forKey: Pref.minFreeGB)
    }
}

enum MessageKind: String, Codable { case text, photo, video }

struct ChatMessage: Identifiable {
    /// Mine: sending → sent (✓) → delivered (✓✓) → seen (✓✓ blue). Theirs: received.
    enum Status: Comparable { case sending, failed, sent, delivered, seen, received }
    let id: UUID
    let fromMe: Bool
    let kind: MessageKind
    var text: String? = nil
    var fileURL: URL? = nil
    var viewOnce = false
    var opened = false
    var reaction: String? = nil
    /// Theirs only: we already told them we saw it.
    var seenSent = false
    var progress: Double? = nil
    var status: Status

    /// 1–3 emoji and nothing else: shown big, without a bubble.
    var isBigEmoji: Bool {
        guard let text, !text.isEmpty, text.count <= 3 else { return false }
        return text.allSatisfy { $0.unicodeScalars.first?.properties.isEmojiPresentation == true || $0.unicodeScalars.count > 1 }
    }
}

struct Envelope: Codable {
    enum Kind: String, Codable { case text, niToken, opened, reaction, hello, location, delivered, seen }
    var kind: Kind
    var id = UUID()
    var text: String? = nil
    var token: Data? = nil
    var lat: Double? = nil
    var lon: Double? = nil
    var alt: Double? = nil
}

struct Peer: Identifiable {
    let id: String
    var kind: String
    var nickname: String?
    var connected = false
    var preciseDistance: Float?
    var direction: simd_float3?
    var bleDistance: Float?
    /// Their GPS position, if they share it.
    var location: CLLocation?
    /// 0…1 while a video from this peer is arriving.
    var incoming: Double?
    var lastSeen = Date()

    var distance: Float? { preciseDistance ?? bleDistance }

    var title: String {
        if let nickname, !nickname.isEmpty { return "\(nickname) (\(kind))" }
        return "\(kind) · \(id)"
    }

    var distanceText: String {
        if let d = preciseDistance { return String(format: "%.2f M", d) }
        if let d = bleDistance { return String(format: "~%.1f M", d) }
        return "—"
    }
}

/// Any other Bluetooth device nearby: maker and type. The advertised name is shown only if the user opts in.
struct BLEDevice: Identifiable {
    let id: UUID
    var kind: String
    var icon: String
    var name: String?
    var distance: Float
    var lastSeen: Date
}
