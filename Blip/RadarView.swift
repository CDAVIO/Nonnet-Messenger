import SwiftUI

struct RootView: View {
    @EnvironmentObject private var service: PeerService

    var body: some View {
        TabView {
            RadarScreen()
                .tabItem { Label("RADAR", systemImage: "location.north.circle") }
            ChatsScreen()
                .tabItem { Label("CHAT", systemImage: "bubble.left.and.bubble.right") }
                .badge(service.totalUnread)
            SettingsScreen()
                .tabItem { Label("SETTINGS", systemImage: "gearshape") }
        }
    }
}

/// Compass radar: only people with NonNet open, placed in their real direction when it is known.
struct RadarScreen: View {
    @EnvironmentObject private var service: PeerService
    @EnvironmentObject private var location: LocationService
    @AppStorage(Pref.maxMeters) private var maxMeters = 10.0

    private var peers: [Peer] {
        service.peers.values
            .filter { ($0.distance ?? 0) <= Float(maxMeters) || $0.connected }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if service.bluetoothOff {
                        Label("TURN ON BLUETOOTH", systemImage: "exclamationmark.triangle")
                            .font(.ui(13))
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .glass(filled: true)
                    }

                    CompassRadar(peers: peers, maxMeters: maxMeters)

                    ForEach(peers) { peer in
                        NavigationLink(value: peer.id) { PeerRow(peer: peer) }
                            .buttonStyle(.plain)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .padding()
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .animation(.smooth(duration: 0.35), value: peers.map(\.id))
            }
            .background(SpaceBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { ChatScreen(peerID: $0) }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            PixelLogo().frame(width: 40, height: 40)
            Text("NonNet").font(.ui(28, .bold))
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                if let heading = location.heading {
                    Text("\(Int(heading.rounded()) % 360)°").font(.ui(26)).monospacedDigit()
                    Text(LocationService.cardinal(heading)).font(.ui(13)).foregroundStyle(Theme.accent)
                } else {
                    Text("—°").font(.ui(26))
                    Text("NO COMPASS").font(.ui(10)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
}

struct PeerRow: View {
    let peer: Peer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Identity.icon(peer.kind))
                .frame(width: 38, height: 38)
                .foregroundStyle(.white)
                .background(Circle().fill(peer.connected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.white.opacity(0.15))))
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.title).font(.ui(15))
                Text(peer.connected ? "● ACTIVE" : "○ CONNECTING…")
                    .font(.ui(11))
                    .foregroundStyle(peer.connected ? Theme.accent : .white.opacity(0.6))
            }
            Spacer()
            DirectionArrow(peer: peer)
            Text(peer.distanceText)
                .font(.ui(15))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.3), value: peer.distanceText)
        }
        .padding(12)
        .glass()
        .contentShape(Rectangle())
    }
}

/// Yellow arrow pointing at the peer from where you hold the phone; "?" when the direction is unknown.
struct DirectionArrow: View {
    let peer: Peer
    @EnvironmentObject private var location: LocationService
    /// Unwrapped angle, so crossing north turns the arrow a few degrees instead of a full spin.
    @State private var shown: Double?

    var body: some View {
        let target = location.screenAngle(for: peer)
        Group {
            if let shown, target != nil {
                Image(systemName: "location.north.fill")
                    .foregroundStyle(Theme.accent)
                    .rotationEffect(.radians(shown))
            } else {
                Text("?").font(.ui(14)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .onAppear { shown = target }
        .onChange(of: target) {
            guard let target else { return }
            guard let current = shown else {
                shown = target
                return
            }
            let delta = remainder(target - current, 2 * .pi)
            withAnimation(.smooth(duration: 0.3)) { shown = current + delta }
        }
    }
}

/// Eases values every frame so the dial and the markers glide instead of jumping.
private final class RadarMotion {
    var heading: Double?
    private var points: [String: CGPoint] = [:]

    func ease(heading target: Double) -> Double {
        guard let current = heading else {
            heading = target
            return target
        }
        var delta = target - current
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let next = current + delta * 0.15
        heading = next
        return next
    }

    /// Eases angle (the short way round) and radius separately, so markers follow the arc.
    func ease(_ key: String, angle: Double, radius: CGFloat) -> (angle: Double, radius: CGFloat) {
        guard let old = points[key] else {
            points[key] = CGPoint(x: angle, y: radius)
            return (angle, radius)
        }
        let a = Double(old.x) + remainder(angle - Double(old.x), 2 * .pi) * 0.15
        let r = old.y + (radius - old.y) * 0.15
        points[key] = CGPoint(x: a, y: r)
        return (a, r)
    }
}

/// The radar, all drawn per frame:
/// - a beveled dial whose ticks turn with the phone while N/E/S/W and degrees stay upright,
/// - a yellow scan sweep with a fading trail and Bluetooth pulses from the center,
/// - people whose direction is known as phone/laptop markers that flash when the sweep passes,
/// - people whose direction is unknown as a dashed ring at their distance (no made-up position).
struct CompassRadar: View {
    let peers: [Peer]
    let maxMeters: Double
    @EnvironmentObject private var location: LocationService
    @State private var motion = RadarMotion()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                draw(&ctx, size: size, t: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 420)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let accent = Theme.accent
        let R = min(size.width, size.height) / 2 - 2
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let field = R - 46 // where people are placed
        let heading = location.heading.map { motion.ease(heading: $0) } ?? 0

        func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
        /// Screen point for an angle measured clockwise from the top of the screen.
        func at(_ radians: Double, _ r: CGFloat) -> CGPoint { CGPoint(x: c.x + r * sin(radians), y: c.y - r * cos(radians)) }
        /// Screen angle for a compass bearing, given where the phone points.
        func screen(_ bearing: Double) -> Double { (bearing - heading) * .pi / 180 }

        // Bevel: stacked rings give the dial depth.
        for i in 0..<6 {
            ctx.stroke(circle(R - CGFloat(i)), with: .color((i < 2 ? Theme.blue : Theme.purple).opacity(0.9 - Double(i) * 0.14)), lineWidth: 1.2)
        }
        ctx.fill(circle(R - 6), with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.10, blue: 0.36), Color(red: 0.05, green: 0.10, blue: 0.28)]),
                                                     startPoint: CGPoint(x: c.x - R, y: c.y - R), endPoint: CGPoint(x: c.x + R, y: c.y + R)))
        ctx.stroke(circle(R - 30), with: .color(.white.opacity(0.18)), lineWidth: 1)
        ctx.fill(circle(R - 31), with: .radialGradient(Gradient(colors: [Color(red: 0.07, green: 0.05, blue: 0.20), Theme.deep]),
                                                      center: c, startRadius: 0, endRadius: R))

        // Ticks turn with the phone.
        for deg in stride(from: 0, to: 360, by: 5) {
            let major = deg % 30 == 0
            var tick = Path()
            tick.move(to: at(screen(Double(deg)), R - 8))
            tick.addLine(to: at(screen(Double(deg)), R - (major ? 22 : 14)))
            ctx.stroke(tick, with: .color(deg == 0 ? accent : .white.opacity(major ? 0.95 : 0.4)), lineWidth: major ? 2.5 : 1)
        }

        // Distance rings with labels.
        for f in [1.0 / 3, 2.0 / 3, 1.0] {
            let r = field * CGFloat(f)
            ctx.stroke(circle(r), with: .color(.white.opacity(f == 1 ? 0.22 : 0.12)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            ctx.draw(Text(String(format: "%.0fM", maxMeters * f)).font(.ui(9)).foregroundColor(.white.opacity(0.45)),
                     at: CGPoint(x: c.x + 4, y: c.y - r + 8), anchor: .leading)
        }

        // Pulses.
        for i in 0..<3 {
            let phase = (t / 2.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            ctx.stroke(circle(field * CGFloat(phase)), with: .color(accent.opacity(0.45 * (1 - phase))), lineWidth: 1.5)
        }

        // Scan sweep: bright edge, long fading trail.
        let sweep = (t / 3).truncatingRemainder(dividingBy: 1) * 2 * .pi
        for step in 0..<40 {
            let a = sweep - Double(step) * 0.03
            var wedge = Path()
            wedge.move(to: c)
            wedge.addLine(to: at(a - 0.03, field))
            wedge.addLine(to: at(a, field))
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(accent.opacity(0.32 * pow(1 - Double(step) / 40, 2.2))))
        }
        var edge = Path()
        edge.move(to: c)
        edge.addLine(to: at(sweep, field))
        ctx.stroke(edge, with: .color(accent), lineWidth: 2)

        // Upright letters and degrees, riding on the turning ring.
        for (label, bearing) in [("N", 0.0), ("E", 90), ("S", 180), ("W", 270)] {
            ctx.draw(Text(label).font(.ui(18)).foregroundColor(bearing == 0 ? accent : .white), at: at(screen(bearing), R - 40))
        }
        for deg in stride(from: 30, to: 360, by: 30) where deg % 90 != 0 {
            ctx.draw(Text("\(deg)").font(.ui(9)).foregroundColor(.white.opacity(0.6)), at: at(screen(Double(deg)), R - 38))
        }

        // Fixed mark: where the top of the phone points.
        var mark = Path()
        mark.move(to: CGPoint(x: c.x, y: c.y - R + 26))
        mark.addLine(to: CGPoint(x: c.x - 7, y: c.y - R + 12))
        mark.addLine(to: CGPoint(x: c.x + 7, y: c.y - R + 12))
        mark.closeSubpath()
        ctx.fill(mark, with: .color(accent))

        /// 1 right as the sweep passes an angle, fading to 0 over ~70°.
        func ping(_ angle: Double) -> Double {
            var d = (sweep - angle).truncatingRemainder(dividingBy: 2 * .pi)
            if d < 0 { d += 2 * .pi }
            return max(0, 1 - d / 1.2)
        }
        func radius(_ peer: Peer) -> CGFloat {
            let meters = peer.distance.map(Double.init) ?? location.gpsDistance(to: peer) ?? maxMeters
            return field * CGFloat(0.18 + 0.82 * min(meters / maxMeters, 1))
        }

        for peer in peers {
            let name = (peer.nickname ?? peer.kind).uppercased()
            guard let angle = location.screenAngle(for: peer, heading: location.heading == nil ? nil : heading) else {
                // Unknown direction: a dashed ring at their distance, label on the ring.
                let shown = motion.ease("ring-" + peer.id, angle: 0, radius: radius(peer)).radius
                ctx.stroke(circle(shown), with: .color(accent.opacity(0.85)), style: StrokeStyle(lineWidth: 2, dash: [6, 6], dashPhase: CGFloat(t * 20)))
                label(&ctx, "\(name) \(peer.distanceText) · DIRECTION ?", at: CGPoint(x: c.x, y: c.y + shown), filled: false)
                continue
            }
            let eased = motion.ease(peer.id, angle: angle, radius: radius(peer))
            let p = at(eased.angle, eased.radius)
            let glow = ping(eased.angle)
            if glow > 0 {
                    let rr = 18 + 14 * (1 - glow)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: 2 * rr, height: 2 * rr)),
                           with: .color(accent.opacity(glow * 0.6)), lineWidth: 1.5)
            }
            let box = CGRect(x: p.x - 15, y: p.y - 15, width: 30, height: 30)
            let disc = Path(ellipseIn: box)
            ctx.fill(disc, with: .linearGradient(Gradient(colors: [Theme.purple, Theme.blue]), startPoint: box.origin, endPoint: CGPoint(x: box.maxX, y: box.maxY)))
            ctx.stroke(disc, with: .color(.white.opacity(0.7)), lineWidth: 1.5)
            ctx.draw(Text(Image(systemName: Identity.icon(peer.kind))).font(.system(size: 14, weight: .bold)).foregroundColor(.white), at: p)
            label(&ctx, "\(name) \(peer.distanceText)", at: CGPoint(x: p.x, y: p.y + 26), filled: true)
        }

        // You, in the middle.
        ctx.fill(circle(7), with: .color(.white))
        ctx.stroke(circle(12), with: .color(accent.opacity(0.7)), lineWidth: 1.5)
    }

    private func label(_ ctx: inout GraphicsContext, _ text: String, at point: CGPoint, filled: Bool) {
        let resolved = ctx.resolve(Text(text).font(.ui(10)).foregroundColor(.white))
        let size = resolved.measure(in: CGSize(width: 400, height: 40))
        let rect = CGRect(x: point.x - size.width / 2 - 7, y: point.y - size.height / 2 - 3, width: size.width + 14, height: size.height + 6)
        let pill = Path(roundedRect: rect, cornerRadius: rect.height / 2)
        ctx.fill(pill, with: .color(filled ? Color(red: 0.10, green: 0.08, blue: 0.28).opacity(0.9) : Theme.deep.opacity(0.85)))
        ctx.stroke(pill, with: .color(filled ? .white.opacity(0.3) : Theme.accent), lineWidth: 1)
        ctx.draw(resolved, at: point)
    }
}

/// The NonNet mark: the app icon, with Apple's rounded corners.
struct PixelLogo: View {
    var body: some View {
        GeometryReader { geo in
            Image("Logo")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: geo.size.width * 0.225, style: .continuous))
        }
    }
}
