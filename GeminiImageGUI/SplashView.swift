import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 1.0
    @State private var rotation: Double = 0.0
    @State private var textGlow: CGFloat = 0.0
    @State private var jiggle: CGFloat = 0.0  // New: For Liquid Glass fluidity
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Environment(\.horizontalSizeClass) var sizeClass: UserInterfaceSizeClass?

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(white: 0.1)
    }

    private var blueGradient: LinearGradient {
        LinearGradient(gradient: Gradient(colors: [Color.indigo.opacity(0.8), Color.blue.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var lightBlueGradient: LinearGradient {
        LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.6)]), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var fontSize: CGFloat {
        sizeClass == .compact ? 50 : 72
    }

    var body: some View {
        ZStack {
            // Background
            backgroundColor
                .ignoresSafeArea()

            // Animated blooming circles
            ZStack {
                ForEach(0..<6) { index in
                    Circle()
                        .fill(index % 2 == 0 ? blueGradient : lightBlueGradient)
                        .frame(width: 120 + CGFloat(index * 60), height: 120 + CGFloat(index * 60))
                        .opacity(opacity - Double(index) * 0.15)
                        .scaleEffect(scale)
                        .rotationEffect(.degrees(rotation + Double(index * 30)))
                        .blendMode(colorScheme == .dark ? .screen : .multiply)
                }
            }
            .blur(radius: 10) // Soft futuristic glow

            // App name with Liquid Glass effect
            Text("ImagenStation")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color.cyan.opacity(0.5), radius: textGlow, x: 0, y: 0)
                .shadow(color: Color.blue.opacity(0.3), radius: textGlow * 2, x: 0, y: 0)
                .scaleEffect(scale * 1.2)
                .opacity(opacity)
                .padding(20)  // Padding for glass container
                .offset(y: jiggle)  // Fluid jiggle
        }
        .onAppear {
            // Bloom expansion animation
            withAnimation(.easeInOut(duration: 2.0)) {
                scale = 1.0
                opacity = 0.4
            }
            // Rotation animation
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                rotation = 360.0
            }
            // Text glow pulse
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                textGlow = 10.0
            }
            // Liquid Glass jiggle (subtle quivering)
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                jiggle = 2.0
            }
        }
    }
}
