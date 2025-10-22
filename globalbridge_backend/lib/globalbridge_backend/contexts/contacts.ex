defmodule GlobalbridgeBackend.Contexts.Contacts do
  @moduledoc """
  Context for managing user contacts with search, sync, and CRUD operations.
  """
  import Ecto.Query
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{Contact, User}

  @doc "Find user by email (case-insensitive)"
  def find_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  @doc "Search users by email pattern (for non-contacts)"
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
      join: u in User,
      on: c.contact_user_id == u.id,
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
      nil ->
        {:error, :not_found}

      contact ->
        contact
        |> Contact.changeset(attrs)
        |> Repo.update()
    end
  end
end
