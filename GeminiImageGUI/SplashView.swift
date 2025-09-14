// SplashView.swift
import SwiftUI

struct SplashView: View {
    let appState = AppState()  // Your shared state instance
    @State private var isActive = false
    
    var body: some View {
        if isActive {
            // Main app content
            ContentView()
                .environmentObject(appState)
        } else {
            ZStack {
                Color.black  // Matches initial black screen for seamless start
                    .ignoresSafeArea()
                
                AbstractBloomExpansionLoading()
                    .frame(width: 200, height: 200)  // Center the animation
            }
            .onAppear {
                // Start animation immediately (no delay here)
                // If you have init tasks, run them async
                DispatchQueue.global().async {
                    // Example: Run heavy startup tasks here (e.g., performOnAppear logic)
                    // appState.performInitialLoads() or similar
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {  // Adjust delay for perceived smoothness
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isActive = true
                        }
                    }
                }
            }
        }
    }
}
