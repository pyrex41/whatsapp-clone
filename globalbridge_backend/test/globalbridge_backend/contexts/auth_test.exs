defmodule GlobalbridgeBackend.Contexts.AuthTest do
  use GlobalbridgeBackend.DataCase, async: true

  alias GlobalbridgeBackend.Contexts.Auth
  alias GlobalbridgeBackend.Schemas.User
  alias GlobalbridgeBackend.Repo

  describe "signup/1" do
    @valid_attrs %{
      "username" => "testuser",
      "phone_number" => "+1234567890",
      "password" => "SecurePassword123",
      "display_name" => "Test User"
    }

    test "creates user with valid attributes and returns tokens" do
      assert {:ok, user, tokens} = Auth.signup(@valid_attrs)
      assert user.username == "testuser"
      assert user.phone_number == "+1234567890"
      assert user.display_name == "Test User"
      assert user.password_hash != nil
      assert user.password_hash != "SecurePassword123"
      assert Map.has_key?(tokens, :access_token)
      assert Map.has_key?(tokens, :refresh_token)
    end

    test "hashes password before storing" do
      {:ok, user, _tokens} = Auth.signup(@valid_attrs)
      assert Bcrypt.verify_pass("SecurePassword123", user.password_hash)
    end

    test "accepts public_key for E2EE setup" do
      attrs = Map.put(@valid_attrs, "public_key", "test_public_key_data")
      {:ok, user, _tokens} = Auth.signup(attrs)
      assert user.public_key == "test_public_key_data"
    end

    test "fails with duplicate username" do
      {:ok, _user, _tokens} = Auth.signup(@valid_attrs)
      assert {:error, %Ecto.Changeset{} = changeset} = Auth.signup(@valid_attrs)
      assert "has already been taken" in errors_on(changeset).username
    end

    test "fails with duplicate phone number" do
      {:ok, _user, _tokens} = Auth.signup(@valid_attrs)
      different_username = Map.put(@valid_attrs, "username", "different")
      assert {:error, %Ecto.Changeset{} = changeset} = Auth.signup(different_username)
      assert "has already been taken" in errors_on(changeset).phone_number
    end

    test "validates phone number format (E.164)" do
      invalid_attrs = Map.put(@valid_attrs, "phone_number", "1234567890")
      assert {:error, %Ecto.Changeset{} = changeset} = Auth.signup(invalid_attrs)
      assert "must be valid E.164 format" in errors_on(changeset).phone_number
    end

    test "validates username length" do
      short_username = Map.put(@valid_attrs, "username", "ab")
      assert {:error, %Ecto.Changeset{} = changeset} = Auth.signup(short_username)
      assert "should be at least 3 character(s)" in errors_on(changeset).username
    end

    test "requires username, phone_number, and password" do
      assert {:error, %Ecto.Changeset{} = changeset} = Auth.signup(%{})
      assert "can't be blank" in errors_on(changeset).username
      assert "can't be blank" in errors_on(changeset).phone_number
      assert "can't be blank" in errors_on(changeset).password_hash
    end
  end

  describe "login/2" do
    setup do
      {:ok, user, _tokens} =
        Auth.signup(%{
          "username" => "loginuser",
          "phone_number" => "+1987654321",
          "password" => "LoginPassword123"
        })

      %{user: user}
    end

    test "authenticates with username and password", %{user: user} do
      assert {:ok, returned_user, tokens} = Auth.login("loginuser", "LoginPassword123")
      assert returned_user.id == user.id
      assert Map.has_key?(tokens, :access_token)
      assert Map.has_key?(tokens, :refresh_token)
    end

    test "authenticates with phone number and password", %{user: user} do
      assert {:ok, returned_user, tokens} = Auth.login("+1987654321", "LoginPassword123")
      assert returned_user.id == user.id
      assert Map.has_key?(tokens, :access_token)
    end

    test "updates is_online to true on login" do
      {:ok, user, _tokens} = Auth.login("loginuser", "LoginPassword123")
      assert user.is_online == true
    end

    test "updates last_seen_at on login" do
      before = DateTime.utc_now()
      {:ok, user, _tokens} = Auth.login("loginuser", "LoginPassword123")
      assert DateTime.compare(user.last_seen_at, before) in [:gt, :eq]
    end

    test "fails with wrong password" do
      assert {:error, :invalid_credentials} = Auth.login("loginuser", "WrongPassword")
    end

    test "fails with non-existent username" do
      assert {:error, :invalid_credentials} = Auth.login("nonexistent", "SomePassword")
    end

    test "fails with non-existent phone" do
      assert {:error, :invalid_credentials} = Auth.login("+9999999999", "SomePassword")
    end
  end

  describe "get_user/1" do
    test "returns user by ID" do
      {:ok, user, _tokens} =
        Auth.signup(%{
          "username" => "getuser",
          "phone_number" => "+1111111111",
          "password" => "Password123"
        })

      assert {:ok, fetched_user} = Auth.get_user(user.id)
      assert fetched_user.id == user.id
      assert fetched_user.username == "getuser"
    end

    test "returns error for non-existent ID" do
      assert {:error, :not_found} = Auth.get_user(Ecto.UUID.generate())
    end
  end

  describe "update_public_key/2" do
    setup do
      {:ok, user, _tokens} =
        Auth.signup(%{
          "username" => "keyuser",
          "phone_number" => "+1222222222",
          "password" => "Password123"
        })

      %{user: user}
    end

    test "updates user's public key", %{user: user} do
      public_key = "new_public_key_data_base64"
      assert {:ok, updated_user} = Auth.update_public_key(user.id, public_key)
      assert updated_user.public_key == public_key
    end

    test "replaces existing public key", %{user: user} do
      Auth.update_public_key(user.id, "old_key")
      assert {:ok, updated_user} = Auth.update_public_key(user.id, "new_key")
      assert updated_user.public_key == "new_key"
    end

    test "returns error for non-existent user" do
      assert {:error, :not_found} = Auth.update_public_key(Ecto.UUID.generate(), "key")
    end
  end

  describe "get_public_key/1" do
    setup do
      {:ok, user, _tokens} =
        Auth.signup(%{
          "username" => "pubkeyuser",
          "phone_number" => "+1333333333",
          "password" => "Password123",
          "public_key" => "user_public_key"
        })

      %{user: user}
    end

    test "returns public key for user", %{user: user} do
      assert {:ok, public_key} = Auth.get_public_key(user.id)
      assert public_key == "user_public_key"
    end

    test "returns error when user has no public key" do
      {:ok, user, _tokens} =
        Auth.signup(%{
          "username" => "nokeyuser",
          "phone_number" => "+1444444444",
          "password" => "Password123"
        })

      assert {:error, :no_public_key} = Auth.get_public_key(user.id)
    end

    test "returns error for non-existent user" do
      assert {:error, :not_found} = Auth.get_public_key(Ecto.UUID.generate())
    end
  end

  describe "update_online_status/2" do
    setup do
      {:ok, user, _tokens} =
        Auth.signup(%{
          "username" => "statususer",
          "phone_number" => "+1555555555",
          "password" => "Password123"
        })

      %{user: user}
    end

    test "updates online status to true", %{user: user} do
      assert {:ok, updated_user} = Auth.update_online_status(user.id, true)
      assert updated_user.is_online == true
    end

    test "updates online status to false", %{user: user} do
      Auth.update_online_status(user.id, true)
      assert {:ok, updated_user} = Auth.update_online_status(user.id, false)
      assert updated_user.is_online == false
    end

    test "updates last_seen_at when going online", %{user: user} do
      before = DateTime.utc_now()
      {:ok, updated_user} = Auth.update_online_status(user.id, true)
      assert DateTime.compare(updated_user.last_seen_at, before) in [:gt, :eq]
    end

    test "returns error for non-existent user" do
      assert {:error, :not_found} = Auth.update_online_status(Ecto.UUID.generate(), true)
    end
  end

  describe "change_password/3" do
    setup do
      {:ok, user, _tokens} =
        Auth.signup(%{
          "username" => "pwduser",
          "phone_number" => "+1666666666",
          "password" => "OldPassword123"
        })

      %{user: user}
    end

    test "changes password with correct current password", %{user: user} do
      assert {:ok, updated_user} =
               Auth.change_password(user.id, "OldPassword123", "NewPassword456")

      assert Bcrypt.verify_pass("NewPassword456", updated_user.password_hash)
      refute Bcrypt.verify_pass("OldPassword123", updated_user.password_hash)
    end

    test "fails with incorrect current password", %{user: user} do
      assert {:error, :invalid_password} =
               Auth.change_password(user.id, "WrongPassword", "NewPassword456")
    end

    test "returns error for non-existent user" do
      assert {:error, :not_found} = Auth.change_password(Ecto.UUID.generate(), "old", "new")
    end
  end

  describe "verify_credentials/2" do
    setup do
      Auth.signup(%{
        "username" => "verifyuser",
        "phone_number" => "+1777777777",
        "password" => "VerifyPassword123"
      })

      :ok
    end

    test "verifies valid credentials" do
      assert {:ok, user} = Auth.verify_credentials("verifyuser", "VerifyPassword123")
      assert user.username == "verifyuser"
    end

    test "fails with invalid credentials" do
      assert {:error, :invalid_credentials} =
               Auth.verify_credentials("verifyuser", "WrongPassword")
    end
  end
end
