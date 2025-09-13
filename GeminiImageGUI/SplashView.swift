// SplashView.swift
import SwiftUI

struct SplashView: View {
    let appState = AppState()  // Create the AppState instance here
    @State private var isActive = false
    
    var body: some View {
        if isActive {
            // Transition to your main app view with environment object
            ContentView()
                .environmentObject(appState)
        } else {
            ZStack {
                Color.black  // Black background
                    .ignoresSafeArea()
                
                AbstractBloomExpansionLoading()
                    .frame(width: 200, height: 200)  // Adjust size as needed
            }
            .onAppear {
                // Delay to show animation (e.g., 2-3 seconds, or until ready)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        isActive = true
                    }
                }
            }
        }
    }
}
