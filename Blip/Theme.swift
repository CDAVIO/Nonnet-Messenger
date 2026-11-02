import SwiftUI
import UIKit

/// Sci-fi glass: deep space background, purple → blue glossy gradients, SF Pro, translucent bars.
enum Theme {
    static let purple = Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xFF / 255)
    static let blue = Color(red: 0x3D / 255, green: 0xA5 / 255, blue: 0xFF / 255)
    /// Single-color accent for text and strokes: halfway between purple and blue.
    static let accent = Color(red: 0x7E / 255, green: 0x8C / 255, blue: 0xFF / 255)
    static let gradient = LinearGradient(colors: [purple, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let deep = Color(red: 0.03, green: 0.03, blue: 0.10)

    static func uiFont(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.font: uiFont(17), .foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.font: uiFont(34, weight: .bold), .foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

extension Font {
    /// SF Pro Rounded, the app's one typeface.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Deep space: dark indigo with a purple glow top-left and a blue glow bottom-right.
struct SpaceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.02, blue: 0.10),
                                    Color(red: 0.06, green: 0.04, blue: 0.18),
                                    Color(red: 0.02, green: 0.05, blue: 0.14)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.purple.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.blue.opacity(0.25), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

/// Glass card: frosted material with a thin light edge, or the glossy purple → blue gradient when filled.
struct Glass: ViewModifier {
    var filled = false
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .foregroundStyle(.white)
            .background {
                if filled {
                    shape.fill(Theme.gradient)
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center)))
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .clipShape(shape)
    }
}

extension View {
    func glass(filled: Bool = false, radius: CGFloat = 16) -> some View { modifier(Glass(filled: filled, radius: radius)) }
}
