namespace GlobalBridge.Networking

open System
open System.Net.Http
open System.Collections.Generic
open System.Net.Http.Json
open System.Net.Http.Headers
open System.Text
open System.Text.Json
open System.Text.Json.Serialization
open System.Threading.Tasks
open GlobalBridge.Core.Auth

/// REST helpers for interacting with Auth0 endpoints and backend provisioning APIs.
module AuthApi =

    type TokenResponse =
        { [<JsonPropertyName("access_token")>] AccessToken: string
          [<JsonPropertyName("refresh_token")>] RefreshToken: string voption
          [<JsonPropertyName("id_token")>] IdToken: string voption
          [<JsonPropertyName("expires_in")>] ExpiresIn: int }

    let private jsonOptions =
        JsonSerializerOptions(PropertyNameCaseInsensitive = true)

    let exchangeAuthorizationCode
        (clientFactory: unit -> HttpClient)
        (config: Auth0Config)
        (codeVerifier: string)
        (authorizationCode: string)
        : Task<AuthTokens> =
        task {
            use client = clientFactory()
            let tokenEndpoint = Uri(config.Domain, "/oauth/token")

            let body =
                [|
                    KeyValuePair("grant_type", "authorization_code")
                    KeyValuePair("client_id", config.ClientId)
                    KeyValuePair("code", authorizationCode)
                    KeyValuePair("code_verifier", codeVerifier)
                    KeyValuePair("redirect_uri", $"{config.CallbackScheme}://callback")
                |]
                |> Array.toList
                |> fun basePairs ->
                    match config.Audience with
                    | Some audience -> KeyValuePair("audience", audience) :: basePairs
                    | None -> basePairs
                |> List.append [ KeyValuePair("scope", "openid profile offline_access") ]
                |> List.toArray
                |> FormUrlEncodedContent

            use! response = client.PostAsync(tokenEndpoint, body)
            response.EnsureSuccessStatusCode() |> ignore

            use! stream = response.Content.ReadAsStreamAsync()
            let! parsed = JsonSerializer.DeserializeAsync<TokenResponse>(stream, jsonOptions)
            let expiresAt = DateTimeOffset.UtcNow.AddSeconds(float parsed.ExpiresIn)

            return
                { AccessToken = parsed.AccessToken
                  RefreshToken = parsed.RefreshToken |> ValueOption.toOption
                  IdToken = parsed.IdToken |> ValueOption.toOption
                  ExpiresAt = expiresAt }
        }

    // ----------------------------
    // Auth0 + Ueberauth handshake
    // ----------------------------

    type Auth0LoginRequest =
        { [<JsonPropertyName("access_token")>] AccessToken: string
          [<JsonPropertyName("device_id")>] DeviceId: string voption }

    type Auth0LoginResponse =
        { [<JsonPropertyName("sub")>] Subject: string
          [<JsonPropertyName("email")>] Email: string voption
          [<JsonPropertyName("name")>] Name: string voption }

    /// POST /auth/auth0/login with the Auth0 access token so Phoenix (Ueberauth) can map the user.
    /// Returns a UserProfile inferred from the backend payload.
    let postAuth0Login
        (clientFactory: unit -> HttpClient)
        (baseAddress: Uri)
        (accessToken: string)
        (deviceId: string option)
        : Task<UserProfile option> =
        task {
            use client = clientFactory()
            client.BaseAddress <- baseAddress
            let payload : Auth0LoginRequest =
                { AccessToken = accessToken
                  DeviceId = deviceId |> Option.map ValueSome |> Option.defaultValue ValueNone }
            use content = JsonContent.Create(payload)
            let! response = client.PostAsync("auth/auth0/login", content)
            if not response.IsSuccessStatusCode then
                return None
            else
                let! stream = response.Content.ReadAsStreamAsync()
                let! mapped = JsonSerializer.DeserializeAsync<Auth0LoginResponse>(stream, jsonOptions)
                if obj.ReferenceEquals(mapped, null) then
                    return None
                else
                    let profile : UserProfile =
                        { Subject = mapped.Subject
                          Name = mapped.Name |> ValueOption.toOption
                          Email = mapped.Email |> ValueOption.toOption }
                    return Some profile
        }

    let refreshToken
        (clientFactory: unit -> HttpClient)
        (config: Auth0Config)
        (refreshToken: string)
        : Task<AuthTokens> =
        task {
            use client = clientFactory()
            let tokenEndpoint = Uri(config.Domain, "/oauth/token")

            let body =
                [|
                    KeyValuePair("grant_type", "refresh_token")
                    KeyValuePair("client_id", config.ClientId)
                    KeyValuePair("refresh_token", refreshToken)
                |]
                |> FormUrlEncodedContent

            use! response = client.PostAsync(tokenEndpoint, body)
            response.EnsureSuccessStatusCode() |> ignore
            use! stream = response.Content.ReadAsStreamAsync()
            let! parsed = JsonSerializer.DeserializeAsync<TokenResponse>(stream, jsonOptions)
            let expiresAt = DateTimeOffset.UtcNow.AddSeconds(float parsed.ExpiresIn)

            return
                { AccessToken = parsed.AccessToken
                  RefreshToken =
                    match parsed.RefreshToken |> ValueOption.toOption with
                    | Some token -> Some token
                    | None -> Some refreshToken
                  IdToken = parsed.IdToken |> ValueOption.toOption
                  ExpiresAt = expiresAt }
        }

    type DeviceRegistrationRequest =
        { DeviceId: string
          PushToken: string option }

    let registerDevice
        (clientFactory: unit -> HttpClient)
        (baseAddress: Uri)
        (accessToken: string)
        (payload: DeviceRegistrationRequest)
        : Task =
        task {
            use client = clientFactory()
            client.BaseAddress <- baseAddress
            client.DefaultRequestHeaders.Authorization <- Headers.AuthenticationHeaderValue("Bearer", accessToken)
            use content = JsonContent.Create(payload)
            use! response = client.PostAsync("api/mobile/devices", content)
            response.EnsureSuccessStatusCode() |> ignore
        }
