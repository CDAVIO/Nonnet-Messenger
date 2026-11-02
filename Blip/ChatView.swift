import AVKit
import PhotosUI
import SwiftUI

private let quickEmoji = ["❤️", "😂", "🔥", "👍", "😮", "😢", "😎", "🙏", "👋", "🎉", "😍", "🤝", "💯", "👀", "😴", "🤙"]
private let reactionEmoji = ["❤️", "😂", "🔥", "👍", "😮", "😢"]

struct ChatsScreen: View {
    @EnvironmentObject private var service: PeerService

    private var ids: [String] {
        Set(service.chats.keys).union(service.peers.values.filter(\.connected).map(\.id)).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if ids.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 40))
                            Text("NO ONE NEARBY").font(.ui(18))
                            Text("Phones running NonNet show up automatically.")
                                .font(.ui(13)).foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.top, 80)
                    }
                    ForEach(ids, id: \.self) { id in
                        let peer = service.peers[id]
                        NavigationLink(value: id) {
                            HStack(spacing: 12) {
                                Image(systemName: Identity.icon(peer?.kind ?? ""))
                                    .frame(width: 38, height: 38)
                                    .glass(filled: true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(peer?.title ?? "Phone · \(id)").font(.ui(15))
                                    Text(lastLine(id)).font(.ui(12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                                }
                                Spacer()
                                if let count = service.unread[id] {
                                    Text("\(count)")
                                        .font(.ui(12, .bold))
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(Theme.gradient))
                                }
                                Text(peer?.connected == true ? peer!.distanceText : "GONE")
                                    .font(.ui(12)).foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(12)
                            .glass()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .background(SpaceBackground())
            .navigationTitle("CHAT")
            .navigationDestination(for: String.self) { ChatScreen(peerID: $0) }
        }
    }

    private func lastLine(_ id: String) -> String {
        guard let last = service.chats[id]?.last else { return "Say hi" }
        if last.kind == .video { return "▶ Video" }
        if last.kind == .photo { return "▣ Photo" }
        return last.text ?? ""
    }
}

struct ChatScreen: View {
    let peerID: String
    @EnvironmentObject private var service: PeerService
    @State private var text = ""
    @State private var showCamera = false
    @State private var showEmoji = false
    @State private var viewing: ChatMessage?
    @State private var picked: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase
    @State private var sentCount = 0
    @FocusState private var typing: Bool

    private var peer: Peer? { service.peers[peerID] }
    private var connected: Bool { peer?.connected == true }
    private var messages: [ChatMessage] { service.chats[peerID] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            if let peer {
                PeerLocator(peer: peer)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            Bubble(msg: msg,
                                   open: { viewing = msg },
                                   react: { service.react($0, to: msg, peerID: peerID) })
                                .id(msg.id)
                                .transition(.asymmetric(insertion: .scale(scale: 0.85, anchor: msg.fromMe ? .bottomTrailing : .bottomLeading)
                                                            .combined(with: .opacity),
                                                        removal: .opacity))
                        }
                    }
                    .padding()
                    .animation(.spring(duration: 0.3, bounce: 0.25), value: messages.count)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) {
                    if let last = messages.last { withAnimation(.smooth) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            if let incoming = peer?.incoming {
                Text("RECEIVING \(Int(incoming * 100))%")
                    .font(.ui(12)).padding(6)
                    .contentTransition(.numericText())
            }

            if !connected {
                Text("NOT CONNECTED · MOVE CLOSER")
                    .font(.ui(12)).foregroundStyle(.white.opacity(0.6)).padding(6)
            }

            if showEmoji {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                    ForEach(quickEmoji, id: \.self) { emoji in
                        Button { send(emoji) } label: { Text(emoji).font(.system(size: 30)) }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                Button { showCamera = true } label: {
                    Image(systemName: "camera.fill").frame(width: 42, height: 42).glass()
                }
                PhotosPicker(selection: $picked, matching: .images) {
                    Image(systemName: "photo.on.rectangle").frame(width: 42, height: 42).glass()
                }
                Button {
                    withAnimation(.spring(duration: 0.25)) { showEmoji.toggle() }
                    if showEmoji { typing = false }
                } label: {
                    Text("☺").font(.system(size: 22)).frame(width: 42, height: 42).glass(filled: showEmoji)
                }
                TextField("MESSAGE…", text: $text)
                    .font(.ui(15))
                    .focused($typing)
                    .padding(.horizontal, 12).frame(height: 42)
                    .glass()
                    .onSubmit { send(text) }
                    .onChange(of: typing) { if typing { withAnimation { showEmoji = false } } }
                Button { send(text) } label: {
                    Image(systemName: "arrow.up").fontWeight(.black).frame(width: 42, height: 42).glass(filled: true)
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .buttonStyle(.plain)
            .disabled(!connected)
            .opacity(connected ? 1 : 0.4)
            .padding()
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpaceBackground())
        .navigationTitle(peer?.title ?? "Phone · \(peerID)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(peer?.distanceText ?? "—")
                    .font(.ui(13)).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth, value: peer?.distanceText)
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: sentCount)
        .sensoryFeedback(.selection, trigger: messages.filter { !$0.fromMe }.count)
        .fullScreenCover(isPresented: $showCamera) {
            CameraScreen { url, kind, viewOnce in
                service.sendMedia(url, kind: kind, viewOnce: viewOnce, to: peerID)
            }
        }
        .fullScreenCover(item: $viewing) { msg in
            MediaViewer(msg: msg) { service.finishedViewing(msg, peerID: peerID) }
        }
        .onChange(of: picked) { uploadPicked() }
        .onAppear { service.activeChat = peerID }
        .onChange(of: scenePhase) { if scenePhase == .active, service.activeChat == peerID { service.markRead(peerID) } }
        .onDisappear { if service.activeChat == peerID { service.activeChat = nil } }
    }

    /// Gallery photos are compressed like camera photos and stay visible (not 1X).
    private func uploadPicked() {
        guard let item = picked else { return }
        picked = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let url = await Task.detached(priority: .userInitiated, operation: { MediaProcessor.compressPhoto(data) }).value
            else { return }
            service.sendMedia(url, kind: .photo, viewOnce: false, to: peerID)
            sentCount += 1
        }
    }

    private func send(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, connected else { return }
        service.sendText(trimmed, to: peerID)
        if value == text { text = "" }
        sentCount += 1
    }
}

private struct Bubble: View {
    let msg: ChatMessage
    let open: () -> Void
    let react: (String) -> Void

    var body: some View {
        HStack {
            if msg.fromMe { Spacer(minLength: 60) }
            VStack(alignment: msg.fromMe ? .trailing : .leading, spacing: -6) {
                content
                    .contextMenu {
                        ForEach(reactionEmoji, id: \.self) { emoji in
                            Button(emoji) { react(emoji) }
                        }
                    }
                    .onTapGesture(count: 2) { react("❤️") }
                if msg.fromMe, msg.status >= .sent, msg.status != .received {
                    ReadReceipt(status: msg.status)
                        .padding(.top, msg.reaction == nil ? 10 : 2)
                        .padding(.trailing, 4)
                }
                if let reaction = msg.reaction {
                    Text(reaction)
                        .font(.system(size: 16))
                        .padding(3)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.4), value: msg.reaction)
            if !msg.fromMe { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder private var content: some View {
        switch msg.kind {
        case .text where msg.isBigEmoji:
            Text(msg.text ?? "").font(.system(size: 52))
        case .text:
            Text(msg.text ?? "")
                .font(.ui(15))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .glass(filled: msg.fromMe, radius: 20)
                .overlay(alignment: .bottomTrailing) {
                    if msg.status == .failed { Image(systemName: "exclamationmark.square").offset(x: 20) }
                }
        case .photo, .video:
            if msg.fromMe {
                mediaLabel(sentTitle, icon: msg.opened ? "eye" : statusIcon, dashed: msg.opened)
            } else if let url = msg.fileURL {
                Button(action: open) {
                    if msg.kind == .photo, !msg.viewOnce, let image = ImageCache.thumbnail(url) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(width: 180, height: 180).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1))
                    } else {
                        mediaLabel("\(kindName) · \(msg.viewOnce ? "1X" : "TAP")", icon: msg.kind == .photo ? "photo" : "play.fill", dashed: false)
                    }
                }
                .buttonStyle(.plain)
            } else {
                mediaLabel("\(kindName) · SEEN", icon: "eye.slash", dashed: true)
            }
        }
    }

    private var kindName: String { msg.kind == .photo ? "PHOTO" : "VIDEO" }

    private var sentTitle: String {
        if msg.opened { return "\(kindName) · SEEN" }
        switch msg.status {
        case .sending: return msg.progress.map { "\(kindName) · SENDING \(Int($0 * 100))%" } ?? "\(kindName) · SENDING…"
        case .failed: return "\(kindName) · FAILED"
        default: return msg.viewOnce ? "\(kindName) · SENT · 1X" : "\(kindName) · SENT"
        }
    }

    private var statusIcon: String {
        switch msg.status {
        case .sending: "arrow.up.square"
        case .failed: "exclamationmark.square"
        default: msg.kind == .photo ? "photo" : "video"
        }
    }

    private func mediaLabel(_ title: String, icon: String, dashed: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.ui(13))
            .padding(.horizontal, 12).padding(.vertical, 12)
            .foregroundStyle(.white.opacity(dashed ? 0.5 : 1))
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(dashed ? AnyShapeStyle(.clear) : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(dashed ? AnyShapeStyle(.white.opacity(0.35)) : AnyShapeStyle(Theme.gradient),
                                        style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 4] : [])))
    }
}

/// Photo: 10 s for view-once (tap to close). Video: plays once for view-once. Then the chat deletes it.
struct MediaViewer: View {
    let msg: ChatMessage
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var saved = false
    @State private var remaining = 10
    @State private var photo: UIImage?
    @State private var openedAt = Date()

    /// 0…1 for the story bar: video playback position, or the 10 s a 1X photo stays (full for kept photos).
    private var viewProgress: Double {
        if let player, let item = player.currentItem {
            let total = item.duration.seconds
            return total.isFinite && total > 0 ? player.currentTime().seconds / total : 0
        }
        return msg.viewOnce ? Date().timeIntervalSince(openedAt) / 10 : 1
    }

    var body: some View {
        ZStack(alignment: .top) {
            SpaceBackground()
            if let image = photo {
                Image(uiImage: image).resizable().scaledToFit().ignoresSafeArea()
            } else if let player {
                VideoPlayer(player: player).ignoresSafeArea().allowsHitTesting(!msg.viewOnce)
            }
            VStack(spacing: 12) {
            TimelineView(.animation) { _ in
                StoryBar(progress: viewProgress, label: nil)
            }
            HStack {
                if msg.viewOnce {
                    Label(msg.kind == .photo ? "1X · \(remaining)S" : "1X · DELETES AFTER", systemImage: "eye").font(.ui(12)).padding(8).glass()
                } else if !saved {
                    Button(action: save) {
                        Label("SAVE", systemImage: "square.and.arrow.down").font(.ui(12)).padding(8).glass()
                    }
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 40, height: 40).glass()
                }
            }
            .buttonStyle(.plain)
            }
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture { if msg.kind == .photo { dismiss() } }
        .task {
            guard let url = msg.fileURL else { return }
            if msg.kind == .photo {
                photo = UIImage(contentsOfFile: url.path)
                guard msg.viewOnce else { return }
                while remaining > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    remaining -= 1
                }
                dismiss()
                return
            }
            let p = AVPlayer(url: url)
            p.isMuted = true
            player = p
            p.play()
            if msg.viewOnce {
                for await _ in NotificationCenter.default.notifications(named: .AVPlayerItemDidPlayToEndTime, object: p.currentItem) {
                    dismiss()
                    break
                }
            }
        }
        .onDisappear {
            player?.pause()
            onClose()
        }
    }

    private func save() {
        guard let url = msg.fileURL else { return }
        if msg.kind == .photo, let image = photo ?? UIImage(contentsOfFile: url.path) {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        } else {
            UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
        }
        saved = true
    }
}

/// Under the chat title: a yellow arrow pointing at the other person, how far, which way, and their coordinates.
private struct PeerLocator: View {
    let peer: Peer
    @EnvironmentObject private var location: LocationService

    var body: some View {
        HStack(spacing: 12) {
            DirectionArrow(peer: peer).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(summary).font(.ui(13))
                if let theirs = peer.location {
                    Text(LocationService.dms(theirs.coordinate)).font(.ui(11)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var summary: String {
        var parts = [peer.distanceText]
        if let mine = location.location, let theirs = peer.location {
            parts.append(LocationService.cardinal(LocationService.bearing(from: mine.coordinate, to: theirs.coordinate)))
            let dz = theirs.altitude - mine.altitude
            if abs(dz) >= 2 { parts.append(String(format: "%@%.0f M %@", dz > 0 ? "↑" : "↓", abs(dz), dz > 0 ? "ABOVE" : "BELOW")) }
        }
        return parts.joined(separator: " · ")
    }
}

/// Decodes chat thumbnails once instead of on every render.
private enum ImageCache {
    private static let cache = NSCache<NSURL, UIImage>()

    static func thumbnail(_ url: URL) -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let full = UIImage(contentsOfFile: url.path) else { return nil }
        // Keep the aspect ratio: the short side becomes 360 px, enough for the 180 pt bubble.
        let scale = min(1, 360 / min(full.size.width, full.size.height))
        let image = full.preparingThumbnail(of: CGSize(width: full.size.width * scale, height: full.size.height * scale)) ?? full
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// ✓ sent, ✓✓ delivered (grey), ✓✓ seen (theme blue, softly glowing).
private struct ReadReceipt: View {
    let status: ChatMessage.Status

    var body: some View {
        let seen = status == .seen
        let double = status >= .delivered
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
            if double { Image(systemName: "checkmark").offset(x: 6) }
        }
        .font(.system(size: 11, weight: .heavy))
        .foregroundStyle(seen ? Theme.blue : .white.opacity(0.4))
        .shadow(color: seen ? Theme.blue.opacity(0.7) : .clear, radius: 4)
        .frame(width: 22, alignment: .leading)
        .animation(.smooth(duration: 0.25), value: status)
    }
}

/// Instagram-style progress: a thin glossy bar that fills left to right, optional seconds on the right.
struct StoryBar: View {
    let progress: Double
    let label: String?

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule()
                        .fill(Theme.gradient)
                        .frame(width: geo.size.width * min(max(progress, 0), 1))
                        .shadow(color: Theme.blue.opacity(0.8), radius: 4)
                }
            }
            .frame(height: 4)
            if let label {
                Text(label).font(.ui(13, .bold)).monospacedDigit().foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .padding(.horizontal, 4)
    }
}
