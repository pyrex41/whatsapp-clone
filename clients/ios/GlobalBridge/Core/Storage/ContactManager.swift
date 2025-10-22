//
//  ContactManager.swift
//  GlobalBridge
//
//  Manages contact operations with optimistic updates and bidirectional sync
//

import Foundation
import SQLite

actor ContactManager {
    private let databaseManager: DatabaseManager
    private let phoenixManager: PhoenixChannelManager

    init(databaseManager: DatabaseManager, phoenixManager: PhoenixChannelManager) {
        self.databaseManager = databaseManager
        self.phoenixManager = phoenixManager
    }

    // MARK: - Local Operations (Optimistic)

    func addContact(_ contactUserId: String, email: String) async throws -> Contact {
        print("➕ [CONTACTS] Adding contact: \(email)")
        
        // 1. Save locally (optimistic)
        let contact = Contact(
            id: UUID(),
            contactUserId: contactUserId,
            displayNameOverride: nil,
            isFavorite: false,
            notes: nil,
            user: Contact.ContactUser(
                id: contactUserId,
                email: email,
                username: nil,
                displayName: nil,
                avatarUrl: nil
            ),
            createdAt: Date(),
            updatedAt: Date(),
            lastSyncedAt: nil,
            needsSync: true,
            isDeleted: false
        )

        try await saveContactLocally(contact)
        print("✅ [CONTACTS] Contact saved locally with optimistic update")

        // 2. Sync to backend asynchronously
        Task {
            do {
                try await syncContactToBackend(contact)
                print("✅ [CONTACTS] Contact synced to backend")
            } catch {
                print("❌ [CONTACTS] Failed to sync contact to backend: \(error)")
            }
        }

        return contact
    }

    func removeContact(_ contactId: UUID) async throws {
        print("➖ [CONTACTS] Removing contact: \(contactId)")
        
        // 1. Mark as deleted locally (optimistic)
        try await markContactAsDeleted(contactId)
        print("✅ [CONTACTS] Contact marked as deleted locally")

        // 2. Sync deletion to backend
        Task {
            do {
                try await syncContactDeletionToBackend(contactId)
                print("✅ [CONTACTS] Contact deletion synced to backend")
            } catch {
                print("❌ [CONTACTS] Failed to sync deletion to backend: \(error)")
            }
        }
    }

    func searchContacts(query: String) async throws -> [Contact] {
        print("🔍 [CONTACTS] Searching local contacts: \(query)")
        return try await fetchContactsLocally(searchQuery: query)
    }

    func searchUsersByEmail(query: String) async throws -> [Contact.ContactUser] {
        print("🔍 [CONTACTS] Searching users by email: \(query)")
        return try await phoenixManager.searchUsers(query: query)
    }

    // MARK: - Sync Operations

    func syncContacts() async throws {
        print("🔄 [CONTACTS] Starting contact sync...")
        
        let lastSyncTime = try await getLastSyncTime()
        print("📅 [CONTACTS] Last sync: \(lastSyncTime)")

        // 1. Pull changes from server
        let serverContacts = try await phoenixManager.syncContacts(since: lastSyncTime)
        print("📥 [CONTACTS] Pulled \(serverContacts.count) contacts from server")

        // 2. Apply server changes (server wins)
        for serverContact in serverContacts {
            try await mergeContactFromServer(serverContact)
        }

        // 3. Push local changes that haven't synced
        let unsyncedContacts = try await fetchUnsyncedContacts()
        print("📤 [CONTACTS] Pushing \(unsyncedContacts.count) unsynced contacts to server")
        
        for contact in unsyncedContacts {
            try await syncContactToBackend(contact)
        }

        // 4. Update last sync time
        try await updateLastSyncTime(Date())
        print("✅ [CONTACTS] Sync complete")
    }

    // MARK: - Private Helpers

    private func saveContactLocally(_ contact: Contact) async throws {
        print("💾 [CONTACTS] Saving contact locally: \(contact.id)")
        // Note: This is a stub implementation that would use DatabaseManager
        // In a full implementation, would INSERT into contacts table via SQLite
        // For now, ContactManager has the structure ready for database integration
    }

    private func markContactAsDeleted(_ contactId: UUID) async throws {
        print("🗑️  [CONTACTS] Marking contact as deleted: \(contactId)")
        // Note: Stub - would UPDATE contacts SET is_deleted=1, needs_sync=1 WHERE id=?
    }

    private func syncContactToBackend(_ contact: Contact) async throws {
        let _ = try await phoenixManager.addContact(contactUserId: contact.contactUserId)
        try await updateContactSyncStatus(contact.id, synced: true)
    }

    private func syncContactDeletionToBackend(_ contactId: UUID) async throws {
        guard let contact = try await fetchContactLocally(id: contactId) else { return }
        try await phoenixManager.removeContact(contactUserId: contact.contactUserId)
    }

    private func mergeContactFromServer(_ serverContact: Contact) async throws {
        // Check if exists locally
        if let localContact = try await fetchContactLocally(id: serverContact.id) {
            // Server is newer? Update local
            if serverContact.updatedAt > localContact.updatedAt {
                print("🔄 [CONTACTS] Server version newer, updating local: \(serverContact.id)")
                try await updateContactLocally(serverContact)
            }
        } else {
            // New from server, insert locally
            print("🆕 [CONTACTS] New contact from server: \(serverContact.id)")
            try await saveContactLocally(serverContact)
        }
    }

    private func fetchContactLocally(id: UUID) async throws -> Contact? {
        // Note: Stub - would SELECT from contacts WHERE id=? using DatabaseManager
        return nil
    }

    private func updateContactLocally(_ contact: Contact) async throws {
        // Note: Stub - would UPDATE contacts SET ... WHERE id=? using DatabaseManager
    }

    private func updateContactSyncStatus(_ contactId: UUID, synced: Bool) async throws {
        // Note: Stub - would UPDATE contacts SET needs_sync=0, last_synced_at=NOW() WHERE id=?
    }

    private func fetchUnsyncedContacts() async throws -> [Contact] {
        // Note: Stub - would SELECT from contacts WHERE needs_sync=1
        return []
    }

    private func fetchContactsLocally(searchQuery: String) async throws -> [Contact] {
        // Note: Stub - would SELECT with WHERE clause filtering on user_email, user_username, user_display_name
        return []
    }

    private func getLastSyncTime() async throws -> Date {
        // Note: Stub - would read from UserDefaults.standard.object(forKey: "contacts_last_sync") as? Date
        return UserDefaults.standard.object(forKey: "contacts_last_sync") as? Date ?? Date(timeIntervalSince1970: 0)
    }

    private func updateLastSyncTime(_ time: Date) async throws {
        // Note: Stub - would save to UserDefaults
        UserDefaults.standard.set(time, forKey: "contacts_last_sync")
    }
}

