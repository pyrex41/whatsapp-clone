//
//  TranslationProviderBadge.swift
//  GlobalBridge
//
//  Provider badge component for displaying translation service provider
//  Shows different badges for Apple, Backend AI, and Hybrid translations
//

import SwiftUI

/// Badge displaying the translation service provider with appropriate icon and styling
struct TranslationProviderBadge: View {
    // MARK: - Properties

    let provider: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: - Provider Info

    private var providerInfo: (icon: String, label: String, color: Color) {
        switch provider.lowercased() {
        case "apple-translation", "apple":
            return ("apple.logo", "Apple", .blue)
        case "backend-ai", "backend", "openai", "anthropic", "claude":
            return ("cloud.fill", "Cloud AI", .purple)
        case "hybrid":
            return ("arrow.triangle.2.circlepath", "Hybrid", .orange)
        default:
            return ("globe", "Unknown", .gray)
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: providerInfo.icon)
                .font(.caption2)
            Text(providerInfo.label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(providerInfo.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(providerInfo.color.opacity(0.15))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Translated by \(providerInfo.label)")
    }
}

/// Detailed provider badge with additional information
struct DetailedTranslationProviderBadge: View {
    let provider: String
    let showPrivacyBadge: Bool

    init(provider: String, showPrivacyBadge: Bool = true) {
        self.provider = provider
        self.showPrivacyBadge = showPrivacyBadge
    }

    private var isPrivate: Bool {
        provider.lowercased().contains("apple")
    }

    var body: some View {
        VStack(spacing: 4) {
            TranslationProviderBadge(provider: provider)

            if showPrivacyBadge && isPrivate {
                HStack(spacing: 2) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 8))
                    Text("Private")
                        .font(.system(size: 9))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.1))
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("All Provider Types") {
    VStack(spacing: 16) {
        Text("Translation Provider Badges")
            .font(.headline)

        TranslationProviderBadge(provider: "apple-translation")
        TranslationProviderBadge(provider: "backend-ai")
        TranslationProviderBadge(provider: "hybrid")
        TranslationProviderBadge(provider: "unknown")

        Divider()

        Text("Detailed Badges")
            .font(.headline)

        DetailedTranslationProviderBadge(provider: "apple-translation")
        DetailedTranslationProviderBadge(provider: "backend-ai")
        DetailedTranslationProviderBadge(provider: "hybrid")
    }
    .padding()
    .previewLayout(.sizeThatFits)
}
