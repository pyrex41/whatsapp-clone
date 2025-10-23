<!-- 89b8d594-e7a9-483a-9784-09d6ad80404a 138da596-df74-4b7d-a403-3e8fe9793204 -->
# Contact Management & Thread Invitation System

## Overview

Implement a contact management system where users can add contacts by email, search existing contacts, and invite contacts to private threads. Backend stores authoritative data with optimistic client updates and bidirectional sync.

## Architecture Decisions

- **Server is source of truth** - eventual consistency model
- **Optimistic updates** - save locally immediately, sync to backend asynchronously
- **No invitation acceptance** initially (but architecture supports adding it later via participant status)
- **Existing users only** - can add email invitations later
- **Search strategy**: Contacts searchable by username/displayName/email; non-contacts only by email

---

## Backend Implementation

### 1. Database Migration - Create Contacts Table

**File:** `globalbridge_backend/priv/repo/migrations/[timestamp]_create_contacts_table.exs`

```elixir
defmodule GlobalbridgeBackend.Repo.Migrations.CreateContactsTable do
  use Ecto.Migration

  def change do
    create table(:contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :contact_user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :display_name_override, :string  # Optional custom name for this contact
      add :is_favorite, :boolean, default: false
      add :notes, :text
      
      timestamps(type: :utc_datetime)
    end

    # Ensure a user can't add the same contact twice
    create unique_index(:contacts, [:user_id, :contact_user_id])
    create index(:contacts, [:user_id])
    create index(:contacts, [:contact_user_id])
    create index(:contacts, [:updated_at])
  end
end
```

### 2. Contact Schema

**File:** `globalbridge_backend/lib/globalbridge_backend/schemas/contact.ex`

```elixir
defmodule GlobalbridgeBackend.Schemas.Contact do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "contacts" do
    belongs_to :user, GlobalbridgeBackend.Schemas.User
    belongs_to :contact_user, GlobalbridgeBackend.Schemas.User
    field :display_name_override, :string
    field :is_favorite, :boolean, default: false
    field :notes, :string
    
    timestamps(type: :utc_datetime)
  end
  
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:user_id, :contact_user_id, :display_name_override, :is_favorite, :notes])
    |> validate_required([:user_id, :contact_user_id])
    |> unique_constraint([:user_id, :contact_user_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:contact_user_id)
    |> validate_not_self_contact()
  end
  
  defp validate_not_self_contact(changeset) do
    user_id = get_field(changeset, :user_id)
    contact_user_id = get_field(changeset, :contact_user_id)
    
    if user_id && contact_user_id && user_id == contact_user_id do
      add_error(changeset, :contact_user_id, "cannot add yourself as a contact")
    else
      changeset
    end
  end
end
```

### 3. Contacts Context

**File:** `globalbridge_backend/lib/globalbridge_backend/contexts/contacts.ex`

```elixir
defmodule GlobalbridgeBackend.Contexts.Contacts do
  import Ecto.Query
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{Contact, User}
  
  @doc "Find user by email"
  def find_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end
  
  @doc "Search users by email/username/display_name (for non-contacts)"
  def search_users_by_email(email) when is_binary(email) do
    email_pattern = "%#{String.downcase(email)}%"
    
    from(u in User,
      where: ilike(u.email, ^email_pattern),
      select: %{
        id: u.id,
        email: u.email,
        username: u.username,
        display_name: u.display_name,
        avatar_url: u.avatar_url
      },
      limit: 20
    )
    |> Repo.all()
  end
  
  @doc "Search contacts by email/username/display_name"
  def search_contacts(user_id, query) when is_binary(query) do
    search_pattern = "%#{String.downcase(query)}%"
    
    from(c in Contact,
      join: u in User, on: c.contact_user_id == u.id,
      where: c.user_id == ^user_id,
      where: 
        ilike(u.email, ^search_pattern) or
        ilike(u.username, ^search_pattern) or
        ilike(u.display_name, ^search_pattern),
      preload: [contact_user: u],
      order_by: [desc: c.is_favorite, desc: c.updated_at]
    )
    |> Repo.all()
  end
  
  @doc "List all contacts for a user"
  def list_contacts(user_id) do
    from(c in Contact,
      where: c.user_id == ^user_id,
      preload: [:contact_user],
      order_by: [desc: c.is_favorite, asc: c.inserted_at]
    )
    |> Repo.all()
  end
  
  @doc "Get contacts modified after timestamp (for sync)"
  def list_contacts_since(user_id, since_timestamp) do
    from(c in Contact,
      where: c.user_id == ^user_id,
      where: c.updated_at > ^since_timestamp,
      preload: [:contact_user],
      order_by: [asc: c.updated_at]
    )
    |> Repo.all()
  end
  
  @doc "Add a contact"
  def add_contact(user_id, contact_user_id, attrs \\ %{}) do
    attrs = Map.merge(attrs, %{user_id: user_id, contact_user_id: contact_user_id})
    
    %Contact{}
    |> Contact.changeset(attrs)
    |> Repo.insert()
  end
  
  @doc "Remove a contact"
  def remove_contact(user_id, contact_user_id) do
    from(c in Contact,
      where: c.user_id == ^user_id,
      where: c.contact_user_id == ^contact_user_id
    )
    |> Repo.delete_all()
  end
  
  @doc "Update contact"
  def update_contact(contact_id, attrs) do
    case Repo.get(Contact, contact_id) do
      nil -> {:error, :not_found}
      contact ->
        contact
        |> Contact.changeset(attrs)
        |> Repo.update()
    end
  end
end
```

### 4. User Channel - Add Contact Operations

**File:** `globalbridge_backend/lib/globalbridge_backend_web/channels/user_channel.ex`

Add these handlers after the existing `handle_in` clauses:

```elixir
# Search for users by email to add as contact
@impl true
def handle_in("search_users", %{"query" => query}, socket) do
  user_id = socket.assigns.user_id
  
  results = Contacts.search_users_by_email(query)
  
  # Filter out current user and existing contacts
  contact_ids = Contacts.list_contacts(user_id)
                |> Enum.map(& &1.contact_user_id)
                |> MapSet.new()
  
  filtered_results = Enum.reject(results, fn user ->
    user.id == user_id or MapSet.member?(contact_ids, user.id)
  end)
  
  {:reply, {:ok, %{users: filtered_results}}, socket}
end

# Search existing contacts
@impl true
def handle_in("search_contacts", %{"query" => query}, socket) do
  user_id = socket.assigns.user_id
  contacts = Contacts.search_contacts(user_id, query)
  
  {:reply, {:ok, %{contacts: format_contacts(contacts)}}, socket}
end

# Get all contacts
@impl true
def handle_in("get_contacts", _payload, socket) do
  user_id = socket.assigns.user_id
  contacts = Contacts.list_contacts(user_id)
  
  {:reply, {:ok, %{contacts: format_contacts(contacts)}}, socket}
end

# Sync contacts (get changes since timestamp)
@impl true
def handle_in("sync_contacts", %{"since" => since_timestamp}, socket) do
  user_id = socket.assigns.user_id
  
  {:ok, since_dt, _} = DateTime.from_iso8601(since_timestamp)
  contacts = Contacts.list_contacts_since(user_id, since_dt)
  
  {:reply, {:ok, %{contacts: format_contacts(contacts), synced_at: DateTime.utc_now()}}, socket}
end

# Add contact
@impl true
def handle_in("add_contact", %{"contact_user_id" => contact_user_id} = payload, socket) do
  user_id = socket.assigns.user_id
  
  case Contacts.add_contact(user_id, contact_user_id, payload) do
    {:ok, contact} ->
      contact = Repo.preload(contact, [:contact_user])
      {:reply, {:ok, format_contact(contact)}, socket}
    
    {:error, changeset} ->
      {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
  end
end

# Remove contact
@impl true
def handle_in("remove_contact", %{"contact_user_id" => contact_user_id}, socket) do
  user_id = socket.assigns.user_id
  
  case Contacts.remove_contact(user_id, contact_user_id) do
    {1, _} -> {:reply, {:ok, %{removed: true}}, socket}
    _ -> {:reply, {:error, %{reason: "Contact not found"}}, socket}
  end
end

# Helper to format contact
defp format_contact(contact) do
  %{
    id: contact.id,
    contact_user_id: contact.contact_user_id,
    display_name_override: contact.display_name_override,
    is_favorite: contact.is_favorite,
    notes: contact.notes,
    user: %{
      id: contact.contact_user.id,
      email: contact.contact_user.email,
      username: contact.contact_user.username,
      display_name: contact.contact_user.display_name,
      avatar_url: contact.contact_user.avatar_url
    },
    created_at: contact.inserted_at,
    updated_at: contact.updated_at
  }
end

defp format_contacts(contacts) do
  Enum.map(contacts, &format_contact/1)
end
```

### 5. Update Thread Creation - Resolve Emails to User IDs

**File:** `globalbridge_backend/lib/globalbridge_backend_web/channels/user_channel.ex`

Update the `create_thread` handler to accept emails and resolve them:

```elixir
@impl true
def handle_in(
      "create_thread",
      %{"thread_type" => type, "participant_ids" => participants, "participant_emails" => emails} = payload,
      socket
    ) do
  user_id = socket.assigns.user_id
  
  # Resolve emails to user IDs
  email_user_ids = Enum.flat_map(emails || [], fn email ->
    case Contacts.find_user_by_email(email) do
      nil -> []
      user -> [user.id]
    end
  end)
  
  # Combine participant IDs and resolved email IDs
  all_participants = ([user_id | participants] ++ email_user_ids) |> Enum.uniq()
  
  attrs = %{
    thread_type: type,
    title: payload["title"],
    participant_ids: all_participants
  }
  
  # ... rest of existing logic
end
```

---

## iOS Implementation

### 6. Contact Model

**File:** `clients/ios/GlobalBridge/Core/Models/Contact.swift`

```swift
import Foundation

struct Contact: Identifiable, Codable, Equatable {
    let id: UUID
    let contactUserId: String  // UUID of the contact user
    var displayNameOverride: String?
    var isFavorite: Bool
    var notes: String?
    let user: ContactUser
    let createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var isDeleted: Bool = false
    
    struct ContactUser: Codable, Equatable {
        let id: String
        let email: String
        let username: String?
        let displayName: String?
        let avatarUrl: String?
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case contactUserId = "contact_user_id"
        case displayNameOverride = "display_name_override"
        case isFavorite = "is_favorite"
        case notes
        case user
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSyncedAt = "last_synced_at"
        case needsSync = "needs_sync"
        case isDeleted = "is_deleted"
    }
    
    var displayName: String {
        displayNameOverride ?? user.displayName ?? user.username ?? user.email
    }
}
```

### 7. Local Contacts Database Schema

**File:** `clients/ios/GlobalBridge/Core/Storage/DatabaseManager.swift`

Add to the database initialization:

```swift
// In setupMainDatabase, add contacts table
let createContactsTable = """
    CREATE TABLE IF NOT EXISTS contacts (
        id TEXT PRIMARY KEY NOT NULL,
        contact_user_id TEXT NOT NULL,
        display_name_override TEXT,
        is_favorite INTEGER DEFAULT 0,
        notes TEXT,
        user_email TEXT NOT NULL,
        user_username TEXT,
        user_display_name TEXT,
        user_avatar_url TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_synced_at TEXT,
        needs_sync INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
    );
"""

let createContactsIndexes = """
    CREATE INDEX IF NOT EXISTS contacts_contact_user_id_index ON contacts(contact_user_id);
    CREATE INDEX IF NOT EXISTS contacts_needs_sync_index ON contacts(needs_sync);
    CREATE INDEX IF NOT EXISTS contacts_is_deleted_index ON contacts(is_deleted);
    CREATE INDEX IF NOT EXISTS contacts_updated_at_index ON contacts(updated_at);
"""
```

### 8. Contact Manager

**File:** `clients/ios/GlobalBridge/Core/Storage/ContactManager.swift`

```swift
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
        
        // 2. Sync to backend asynchronously
        Task {
            try? await syncContactToBackend(contact)
        }
        
        return contact
    }
    
    func removeContact(_ contactId: UUID) async throws {
        // 1. Mark as deleted locally (optimistic)
        try await markContactAsDeleted(contactId)
        
        // 2. Sync deletion to backend
        Task {
            try? await syncContactDeletionToBackend(contactId)
        }
    }
    
    func searchContacts(query: String) async throws -> [Contact] {
        // Search local contacts
        return try await fetchContactsLocally(searchQuery: query)
    }
    
    func searchUsersByEmail(query: String) async throws -> [Contact.ContactUser] {
        // Search backend for non-contact users
        return try await phoenixManager.searchUsers(query: query)
    }
    
    // MARK: - Sync Operations
    
    func syncContacts() async throws {
        let lastSyncTime = try await getLastSyncTime()
        
        // 1. Pull changes from server
        let serverContacts = try await phoenixManager.syncContacts(since: lastSyncTime)
        
        // 2. Apply server changes (server wins)
        for serverContact in serverContacts {
            try await mergeContactFromServer(serverContact)
        }
        
        // 3. Push local changes that haven't synced
        let unsyncedContacts = try await fetchUnsyncedContacts()
        for contact in unsyncedContacts {
            try await syncContactToBackend(contact)
        }
        
        // 4. Update last sync time
        try await updateLastSyncTime(Date())
    }
    
    // MARK: - Private Helpers
    
    private func saveContactLocally(_ contact: Contact) async throws {
        // Insert into SQLite
    }
    
    private func markContactAsDeleted(_ contactId: UUID) async throws {
        // Mark is_deleted = 1, needs_sync = 1
    }
    
    private func syncContactToBackend(_ contact: Contact) async throws {
        let result = try await phoenixManager.addContact(contactUserId: contact.contactUserId)
        // Update local with server response
        try await updateContactSyncStatus(contact.id, synced: true)
    }
    
    private func mergeContactFromServer(_ serverContact: Contact) async throws {
        // Check if exists locally
        if let localContact = try await fetchContactLocally(id: serverContact.id) {
            // Server is newer? Update local
            if serverContact.updatedAt > localContact.updatedAt {
                try await updateContactLocally(serverContact)
            }
        } else {
            // New from server, insert locally
            try await saveContactLocally(serverContact)
        }
    }
}
```

### 9. Phoenix Contact Methods

**File:** `clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixChannelManager.swift`

Add contact-related methods:

```swift
public func searchUsers(query: String) async throws -> [Contact.ContactUser] {
    guard let channel = channel(for: "user:\(currentUserId)") else {
        throw PhoenixError.channelNotJoined
    }
    
    return try await withCheckedThrowingContinuation { continuation in
        channel.push("search_users", payload: ["query": query])
            .receive("ok") { response in
                // Parse and return users
            }
            .receive("error") { _ in
                continuation.resume(throwing: PhoenixError.operationFailed)
            }
    }
}

public func addContact(contactUserId: String) async throws -> Contact {
    // Push "add_contact" to user channel
}

public func syncContacts(since: Date) async throws -> [Contact] {
    // Push "sync_contacts" to user channel
}
```

### 10. Thread Creation UI - Add Contact Selection

**File:** `clients/ios/GlobalBridge/Features/Threads/CreateThreadView.swift`

Update to include contact search and email input:

```swift
struct CreateThreadView: View {
    @State private var searchQuery = ""
    @State private var contacts: [Contact] = []
    @State private var searchResults: [Contact.ContactUser] = []
    @State private var selectedParticipants: Set<String> = []
    @State private var emailInput = ""
    
    var body: some View {
        VStack {
            // Search contacts
            TextField("Search contacts or enter email", text: $searchQuery)
                .onChange(of: searchQuery) { _, newValue in
                    searchContactsOrEmail(newValue)
                }
            
            // Show contacts matching search
            List(contacts) { contact in
                ContactRow(contact: contact) {
                    toggleSelection(contact.contactUserId)
                }
            }
            
            // Show non-contact users matching email search
            if !searchResults.isEmpty {
                Section("Search Results") {
                    ForEach(searchResults, id: \.id) { user in
                        UserRow(user: user) {
                            toggleSelection(user.id)
                        }
                    }
                }
            }
            
            // Create button
            Button("Create Thread") {
                createThread()
            }
            .disabled(selectedParticipants.isEmpty)
        }
    }
    
    private func searchContactsOrEmail(_ query: String) {
        Task {
            // Search contacts first
            contacts = try await contactManager.searchContacts(query: query)
            
            // If looks like email, search non-contacts
            if query.contains("@") {
                searchResults = try await contactManager.searchUsersByEmail(query: query)
            }
        }
    }
}
```

---

## Testing Plan

1. **Contact Addition:**

   - Add contact by email
   - Verify saved locally immediately
   - Verify synced to backend
   - Verify appears in contacts list

2. **Contact Sync:**

   - Add contact on Device A
   - Log in on Device B
   - Verify contact appears after sync

3. **Contact Deletion:**

   - Delete contact locally
   - Verify removed from list
   - Verify deletion syncs to server
   - Verify deletion syncs to other devices

4. **Thread Creation:**

   - Create thread with contacts
   - Create thread with email lookup
   - Verify all participants see thread
   - Verify messages work correctly

5. **Sync Conflict Resolution:**

   - Add contact offline
   - Delete same contact on server
   - Come back online
   - Verify server state wins

---

## Future Enhancements

**Invitation Acceptance (when ready):**

- Add `status` field to `thread_participants` table (`active`, `pending`, `declined`)
- Update thread channel authorization to check status
- Add UI for accepting/declining invitations
- Backend changes are minimal since architecture supports it

**Email Invitations (when ready):**

- Add email service integration
- Create invitation tokens
- Send invitation emails
- Handle signup with invitation token
- Auto-add to thread after signup