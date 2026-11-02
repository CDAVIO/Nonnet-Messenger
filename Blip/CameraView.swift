import SwiftUI

/// Photos and silent 360p video, max 10 s. Flash on the front camera = white ring light around the preview
/// (the controls turn black so they stay visible); on the back camera = LED torch.
struct CameraScreen: View {
    let onSend: (URL, MessageKind, Bool) -> Void

    private enum Mode { case photo, video }

    private static let speeds: [Double] = [1, 1.5, 2]

    @StateObject private var camera = CameraController()
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .video
    @State private var flashOn = false
    @State private var speed: Double = 1
    @State private var viewOnce = true
    @State private var processing = false
    @State private var savedBrightness: CGFloat?
    /// Set when the camera closes, so a recording still finishing is thrown away instead of sent.
    @State private var cancelled = false

    private var ringLight: Bool { flashOn && camera.position == .front }
    private var ink: Color { ringLight ? .black : .white }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()

            if ringLight {
                RingLight().ignoresSafeArea().transition(.opacity)
            }

            VStack(spacing: 12) {
                if let start = camera.recordStart {
                    TimelineView(.animation) { context in
                        let elapsed = context.date.timeIntervalSince(start) / speed
                        StoryBar(progress: elapsed / MediaProcessor.maxVideoSeconds,
                                 label: "\(Int(min(elapsed, MediaProcessor.maxVideoSeconds)))s / 10s")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.4)))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                topBar
                Spacer()
                bottomBar
            }
            .padding()

            if processing {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(mode == .photo ? "COMPRESSING…" : "360P…").font(.ui(14))
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
                .foregroundStyle(.white)
            }
        }
        .foregroundStyle(ink)
        .animation(.easeOut(duration: 0.2), value: ringLight)
        .onAppear { camera.start() }
        .onDisappear {
            cancelled = true
            camera.stop()
            setMaxBrightness(false)
        }
        .onChange(of: ringLight) { setMaxBrightness(ringLight) }
        .onChange(of: flashOn) { camera.setTorch(flashOn && camera.position == .back) }
        .onChange(of: camera.position) { camera.setTorch(flashOn && camera.position == .back) }
        .sensoryFeedback(.impact(weight: .medium), trigger: camera.isRecording)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            pixelButton(icon: "xmark") { dismiss() }
            Spacer()
            pixelButton(icon: flashOn ? "bolt.fill" : "bolt.slash", label: flashOn ? "ON" : "OFF") { flashOn.toggle() }
            if mode == .video {
                pixelButton(label: speed == 1.5 ? "1.5X" : "\(Int(speed))X") {
                    speed = Self.speeds[(Self.speeds.firstIndex(of: speed)! + 1) % Self.speeds.count]
                }
                .disabled(camera.isRecording)
            }
            pixelButton(icon: viewOnce ? "eye" : "infinity", label: viewOnce ? "1X" : "∞", filled: viewOnce) { viewOnce.toggle() }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                modeButton("PHOTO", .photo)
                modeButton("VIDEO", .video)
            }
            .disabled(camera.isRecording)

            Text(mode == .photo ? "PHOTO · COMPRESSED"
                 : camera.isRecording ? "MAX \(Int(MediaProcessor.maxVideoSeconds * speed))S → 10S"
                 : "VIDEO 360P · 10S · SILENT")
                .font(.ui(12))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(ringLight ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial)))

            HStack {
                Color.clear.frame(width: 48, height: 48)
                Spacer()
                ShutterButton(ink: ink, isVideo: mode == .video, recordStart: camera.recordStart, speed: speed, action: shutter)
                Spacer()
                pixelButton(icon: "arrow.triangle.2.circlepath.camera") { camera.switchCamera() }
                    .disabled(camera.isRecording || !camera.hasBackCamera)
            }
        }
    }

    private func shutter() {
        if mode == .photo {
            camera.takePhoto { data in
                guard let data, !cancelled else { return }
                processing = true
                Task.detached(priority: .userInitiated) {
                    let url = MediaProcessor.compressPhoto(data)
                    await MainActor.run {
                        processing = false
                        if let url { onSend(url, .photo, viewOnce) }
                        dismiss()
                    }
                }
            }
            return
        }
        if camera.isRecording {
            camera.stopRecording()
            return
        }
        camera.startRecording(speed: speed) { raw in
            guard let raw else { return }
            guard !cancelled else {
                try? FileManager.default.removeItem(at: raw)
                return
            }
            processing = true
            Task {
                let url = await MediaProcessor.exportVideo(raw, speed: speed)
                processing = false
                if let url { onSend(url, .video, viewOnce) }
                dismiss()
            }
        }
    }

    private func setMaxBrightness(_ on: Bool) {
        let screen = UIScreen.main
        if on {
            savedBrightness = screen.brightness
            screen.brightness = 1
        } else if let saved = savedBrightness {
            screen.brightness = saved
            savedBrightness = nil
        }
    }

    private func modeButton(_ title: String, _ value: Mode) -> some View {
        Button { withAnimation(.smooth(duration: 0.2)) { mode = value } } label: {
            Text(title)
                .font(.ui(13))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(mode == value ? (ringLight ? Color.white : Color.black) : ink)
                .background(Capsule().fill(mode == value ? ink : Color.clear))
                .overlay(Capsule().stroke(ink.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func pixelButton(icon: String? = nil, label: String? = nil, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                if let label { Text(label).font(.ui(13)) }
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 48, minHeight: 48)
            .foregroundStyle(filled ? Color.white : ink)
            .background(Capsule().fill(filled ? AnyShapeStyle(Theme.gradient) : (ringLight ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial))))
            .overlay(Capsule().stroke(ink.opacity(0.4), lineWidth: 1))
        }
    }
}

/// White frame around a rounded window onto the preview: lights the face, keeps the preview visible.
private struct RingLight: View {
    var body: some View {
        GeometryReader { geo in
            let inner = CGRect(x: 26, y: geo.safeAreaInsets.top + 92,
                               width: geo.size.width - 52,
                               height: geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - 92 - 190)
            Path { p in
                p.addRect(CGRect(origin: .zero, size: geo.size))
                p.addRoundedRect(in: inner, cornerSize: CGSize(width: 28, height: 28))
            }
            .fill(.white, style: FillStyle(eoFill: true))
        }
    }
}

/// Ring fills over 10 s × speed of real time; the center shows seconds of the final 10 s video.
private struct ShutterButton: View {
    let ink: Color
    let isVideo: Bool
    let recordStart: Date?
    let speed: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(paused: recordStart == nil)) { timeline in
                let elapsed = recordStart.map { timeline.date.timeIntervalSince($0) } ?? 0
                let total = MediaProcessor.maxVideoSeconds * speed
                ZStack {
                    Circle().stroke(ink.opacity(0.3), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(elapsed / total, 1))
                        .stroke(ink, style: StrokeStyle(lineWidth: 6))
                        .rotationEffect(.degrees(-90))
                    if recordStart != nil {
                        Rectangle().fill(ink).frame(width: 32, height: 32)
                        Text("\(Int(min(elapsed / speed, MediaProcessor.maxVideoSeconds)))")
                            .font(.ui(14))
                            .foregroundStyle(ink == .white ? Color.black : Color.white)
                    } else {
                        Circle().fill(ink).padding(11)
                        if isVideo { Rectangle().fill(ink == .white ? Color.black : Color.white).frame(width: 12, height: 12) }
                    }
                }
                .frame(width: 82, height: 82)
                .animation(.spring(duration: 0.25), value: recordStart == nil)
            }
        }
        .buttonStyle(.plain)
    }
}
