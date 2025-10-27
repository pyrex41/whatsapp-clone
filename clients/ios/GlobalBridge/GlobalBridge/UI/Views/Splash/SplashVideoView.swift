//
//  SplashAnimationView.swift
//  GlobalBridge
//
//  Created by Claude on 10/26/25.
//

import SwiftUI

struct SplashAnimationView: View {
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            // Same dark blue background as the image
            Color(red: 0.14, green: 0.18, blue: 0.27)
                .ignoresSafeArea()

            Image("LaunchScreenImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
        }
        .opacity(opacity)
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // Zoom out animation (1.5x to 1.0x scale)
        withAnimation(.easeOut(duration: 1.2)) {
            scale = 1.0
        }

        // Start fade out after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 0
            }

            // Dismiss after fade completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isPresented = false
            }
        }
    }
}

#Preview {
    SplashAnimationView(isPresented: .constant(true))
}
