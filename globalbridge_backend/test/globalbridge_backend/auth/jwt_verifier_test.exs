defmodule GlobalbridgeBackend.Auth.JWTVerifierTest do
  use GlobalbridgeBackend.DataCase

  alias GlobalbridgeBackend.Auth.JWTVerifier

  describe "verify_token/1" do
    test "returns error for malformed tokens" do
      assert {:error, _reason} = JWTVerifier.verify_token("not.a.valid.jwt")
      assert {:error, _reason} = JWTVerifier.verify_token("invalid-token")
      assert {:error, _reason} = JWTVerifier.verify_token("")
    end

    test "returns error for tokens with missing kid in header" do
      # Create a token without a kid (Key ID) in the header
      # This should fail during the extract_kid step
      token_without_kid = create_test_jwt_without_kid()
      assert {:error, :missing_kid} = JWTVerifier.verify_token(token_without_kid)
    end

    test "returns error when JWKS cache doesn't have the key" do
      # Create a token with a kid that doesn't exist in cache
      token_with_unknown_kid = create_test_jwt_with_unknown_kid()
      assert {:error, :key_not_found} = JWTVerifier.verify_token(token_with_unknown_kid)
    end

    # Note: Full integration tests with real Auth0 tokens require:
    # 1. Valid Auth0 test account
    # 2. Test tokens from Auth0
    # 3. JWKS cache populated with test keys
    # These should be implemented as integration tests with proper test fixtures
  end

  describe "decode_claims/1" do
    test "extracts claims without verification" do
      # Create a simple JWT for testing claim extraction
      token = create_simple_jwt(%{
        "sub" => "user123",
        "email" => "test@example.com",
        "name" => "Test User",
        "exp" => DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()
      })

      assert {:ok, claims} = JWTVerifier.decode_claims(token)
      assert claims["sub"] == "user123"
      assert claims["email"] == "test@example.com"
    end

    test "returns error for invalid JWT structure" do
      assert {:error, _reason} = JWTVerifier.decode_claims("not-a-jwt")
    end
  end

  # Helper functions for creating test JWTs

  defp create_simple_jwt(claims) do
    # Create a basic JWT structure for testing
    # Note: This is NOT a valid signed JWT, just for structure testing
    header = %{
      "alg" => "RS256",
      "typ" => "JWT",
      "kid" => "test-key-id"
    }

    header_b64 = header |> Jason.encode!() |> Base.url_encode64(padding: false)
    claims_b64 = claims |> Jason.encode!() |> Base.url_encode64(padding: false)
    signature = "fake-signature"

    "#{header_b64}.#{claims_b64}.#{signature}"
  end

  defp create_test_jwt_without_kid do
    header = %{
      "alg" => "RS256",
      "typ" => "JWT"
      # Intentionally missing "kid"
    }

    claims = %{
      "sub" => "user123",
      "exp" => DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()
    }

    header_b64 = header |> Jason.encode!() |> Base.url_encode64(padding: false)
    claims_b64 = claims |> Jason.encode!() |> Base.url_encode64(padding: false)

    "#{header_b64}.#{claims_b64}.fake-signature"
  end

  defp create_test_jwt_with_unknown_kid do
    header = %{
      "alg" => "RS256",
      "typ" => "JWT",
      "kid" => "unknown-key-that-does-not-exist-in-cache"
    }

    claims = %{
      "sub" => "user123",
      "exp" => DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()
    }

    header_b64 = header |> Jason.encode!() |> Base.url_encode64(padding: false)
    claims_b64 = claims |> Jason.encode!() |> Base.url_encode64(padding: false)

    "#{header_b64}.#{claims_b64}.fake-signature"
  end

  # TODO: Add integration tests with real Auth0 tokens
  # These would require:
  # 1. Test Auth0 account configuration
  # 2. Generated test tokens from Auth0
  # 3. Mocked or test JWKS endpoint
  # 4. Tests for claim validation (issuer, audience, expiration)
  #
  # Example structure:
  # describe "verify_token/1 with real Auth0 tokens" do
  #   @tag :integration
  #   test "accepts valid Auth0 token with correct claims" do
  #     token = fetch_valid_auth0_test_token()
  #     assert {:ok, claims} = JWTVerifier.verify_token(token)
  #     assert claims["iss"] =~ "auth0.com"
  #   end
  #
  #   @tag :integration
  #   test "rejects expired Auth0 token" do
  #     token = fetch_expired_auth0_test_token()
  #     assert {:error, :token_expired} = JWTVerifier.verify_token(token)
  #   end
  #
  #   @tag :integration
  #   test "rejects token with invalid audience" do
  #     token = create_auth0_token_with_wrong_audience()
  #     assert {:error, {:invalid_audience, _}} = JWTVerifier.verify_token(token)
  #   end
  # end
end
