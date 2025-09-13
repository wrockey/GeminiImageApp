import SwiftUI

struct AbstractBloomExpansionLoading: View {
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 1.0
    @State private var rotation: Double = 0.0

    var body: some View {
        ZStack {
            ForEach(0..<5) { index in
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [Color.indigo, Color.cyan]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100 + CGFloat(index * 50), height: 100 + CGFloat(index * 50))
                    .opacity(opacity - Double(index) * 0.2)
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(rotation))
                    .blendMode(.screen) // For a glowing, overlapping effect
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                scale = 1.0
                opacity = 0.5
            }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                rotation = 360.0
            }
        }
    }
}
