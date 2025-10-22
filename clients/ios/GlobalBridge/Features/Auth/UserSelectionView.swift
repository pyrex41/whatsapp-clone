//
//  UserSelectionView.swift
//  GlobalBridge
//
//  Test user selection screen for development/testing
//

import SwiftUI

struct TestUser: Identifiable {
    let id: String
    let username: String
    let displayName: String
    let token: String
    let emoji: String
}

struct UserSelectionView: View {
    let onUserSelected: (TestUser) -> Void
    
    private let testUsers = [
        TestUser(
            id: "alice",
            username: "alice",
            displayName: "Alice Smith",
            token: "test-token-alice",
            emoji: "👩"
        ),
        TestUser(
            id: "bob",
            username: "bob",
            displayName: "Bob Johnson",
            token: "test-token-bob",
            emoji: "👨"
        ),
        TestUser(
            id: "testuser",
            username: "testuser",
            displayName: "Test User",
            token: "test-token-testuser",
            emoji: "🧪"
        )
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "message.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("GlobalBridge")
                        .font(.largeTitle.bold())
                    
                    Text("Select Test User")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                VStack(spacing: 16) {
                    ForEach(testUsers) { user in
                        Button {
                            onUserSelected(user)
                        } label: {
                            HStack(spacing: 16) {
                                Text(user.emoji)
                                    .font(.system(size: 40))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text("@\(user.username)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                Text("⚠️ Development Only")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }
}

#Preview {
    UserSelectionView { user in
        print("Selected: \(user.displayName)")
    }
}

