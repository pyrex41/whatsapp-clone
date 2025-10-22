namespace GlobalBridge.iOS.Auth

open System
open System.Security.Cryptography
open System.Net
open System.Net.Http
open System.Text
open System.Threading.Tasks
open AuthenticationServices
open Foundation
open UIKit
open GlobalBridge.Core.Auth
open GlobalBridge.Core
open GlobalBridge.Networking.AuthApi
open GlobalBridge.iOS.Storage

[<AllowNullLiteral>]
type private AuthPresentationContext(window: UIWindow) =
    inherit NSObject()
    interface IASWebAuthenticationPresentationContextProviding with
        member _.GetPresentationAnchor _ = window

type AuthCoordinatorDependencies =
    { Config: Auth0Config
      HttpClientFactory: unit -> System.Net.Http.HttpClient
      BackendBaseUri: Uri
      Dispatch: AuthMsg -> unit }

/// Coordinates the Auth0 PKCE flow, token persistence, and device registration.
type AuthCoordinator(deps: AuthCoordinatorDependencies) =

    let codeVerifierLength = 64
    let accessTokenKey = "access_token"
    let refreshTokenKey = "refresh_token"
    let idTokenKey = "id_token"
    let expiryKey = "expires_at"
    let refreshBuffer = TimeSpan.FromMinutes 2.

    let mutable cachedTokens : AuthTokens option = None
    let mutable currentProfile : UserProfile option = None

    let parseProfile (idToken: string option) =
        match idToken with
        | None -> None
        | Some token ->
            let segments = token.Split('.')
            if segments.Length < 2 then
                None
            else
                let payload = segments.[1]
                let padded =
                    payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=')
                        .Replace('-', '+')
                        .Replace('_', '/')
                let bytes = Convert.FromBase64String(padded)
                let json = Encoding.UTF8.GetString bytes
                use doc = System.Text.Json.JsonDocument.Parse(json)
                let subject =
                    let mutable prop = Unchecked.defaultof<System.Text.Json.JsonElement>
                    if doc.RootElement.TryGetProperty("sub", &prop) then
                        prop.GetString()
                    else
                        null
                if String.IsNullOrWhiteSpace subject then
                    None
                else
                    let name =
                        let mutable prop = Unchecked.defaultof<System.Text.Json.JsonElement>
                        if doc.RootElement.TryGetProperty("name", &prop) then
                            prop.GetString()
                        else
                            null
                    let email =
                        let mutable prop = Unchecked.defaultof<System.Text.Json.JsonElement>
                        if doc.RootElement.TryGetProperty("email", &prop) then
                            prop.GetString()
                        else
                            null
                    Some
                        { UserProfile.Subject = subject
                          Name = Option.ofObj name
                          Email = Option.ofObj email }

    let loadTokens () =
        match cachedTokens with
        | Some tokens -> Some tokens
        | None ->
            match TokenStore.read accessTokenKey, TokenStore.readDate expiryKey with
            | Some access, Some expiry ->
                let refresh = TokenStore.read refreshTokenKey
                let idToken = TokenStore.read idTokenKey
                let tokens =
                    { AccessToken = access
                      RefreshToken = refresh
                      IdToken = idToken
                      ExpiresAt = expiry }
                cachedTokens <- Some tokens
                currentProfile <- parseProfile tokens.IdToken
                Some tokens
            | _ -> None

    let generateCodeVerifier () =
        let randomBytes = RandomNumberGenerator.GetBytes(codeVerifierLength)
        Convert.ToBase64String(randomBytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_')

    let generateCodeChallenge (verifier: string) =
        let bytes = Encoding.ASCII.GetBytes verifier
        use sha = SHA256.Create()
        let digest = sha.ComputeHash bytes
        Convert.ToBase64String(digest)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_')

    let buildAuthorizeUrl (codeChallenge: string) =
        let baseUri = Uri(deps.Config.Domain, "/authorize")
        let builder = UriBuilder(baseUri)
        let query =
            [|
                "response_type=code"
                $"client_id={deps.Config.ClientId}"
                $"redirect_uri={deps.Config.CallbackScheme}://callback"
                "scope=openid%20profile%20offline_access"
                $"code_challenge={codeChallenge}"
                "code_challenge_method=S256"
            |]
            |> Array.toList
            |> fun baseList ->
                match deps.Config.Audience with
                | Some audience -> baseList @ [ $"audience={Uri.EscapeDataString(audience)}" ]
                | None -> baseList
        builder.Query <- String.Join("&", query)
        builder.Uri

    let persistTokens (tokens: AuthTokens) =
        TokenStore.save accessTokenKey tokens.AccessToken

        match tokens.RefreshToken with
        | Some refresh -> TokenStore.save refreshTokenKey refresh
        | None -> ()

        match tokens.IdToken with
        | Some idToken -> TokenStore.save idTokenKey idToken
        | None -> ()

        TokenStore.saveDate expiryKey tokens.ExpiresAt
        cachedTokens <- Some tokens
        currentProfile <- parseProfile tokens.IdToken


    let parseQueryParameters (uri: Uri) =
        uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries)
        |> Array.choose (fun pair ->
            let parts = pair.Split('=')
            if parts.Length = 2 then
                let key = Uri.UnescapeDataString(parts.[0])
                let value = Uri.UnescapeDataString(parts.[1])
                Some(key, value)
            else
                None)
        |> dict

    member _.RestoreSession() =
        match loadTokens () with
        | Some tokens ->
            currentProfile <- parseProfile tokens.IdToken
            Some (tokens, currentProfile)
        | None -> None

    member this.SignOut() =
        TokenStore.delete accessTokenKey
        TokenStore.delete refreshTokenKey
        TokenStore.delete idTokenKey
        TokenStore.delete expiryKey
        cachedTokens <- None
        currentProfile <- None
        deps.Dispatch Logout

    member _.CurrentTokens = loadTokens()
    member _.CurrentProfile = currentProfile

    member this.RefreshIfNeededAsync() =
        task {
            match loadTokens () with
            | Some tokens when tokens.ExpiresAt - DateTimeOffset.UtcNow > refreshBuffer ->
                return Some tokens
            | Some tokens ->
                match tokens.RefreshToken with
                | Some refresh ->
                    try
                        let! refreshed = refreshToken deps.HttpClientFactory deps.Config refresh
                        persistTokens refreshed
                        deps.Dispatch (LoginSucceeded (refreshed, currentProfile))
                        return Some refreshed
                    with ex ->
                        match ex with
                        | :? HttpRequestException as httpEx when httpEx.StatusCode.HasValue && httpEx.StatusCode.Value = HttpStatusCode.Unauthorized ->
                            this.SignOut()
                        | _ -> ()
                        deps.Dispatch (LoginFailed ex.Message)
                        return None
                | None ->
                    this.SignOut()
                    deps.Dispatch (LoginFailed "Refresh token unavailable.")
                    return None
            | None -> return None
        }

    member this.StartLoginAsync(window: UIWindow) =
        task {
            deps.Dispatch StartLogin
            let codeVerifier = generateCodeVerifier()
            let codeChallenge = generateCodeChallenge codeVerifier
            let authorizeUrl = buildAuthorizeUrl codeChallenge

            let tcs = TaskCompletionSource<NSUrl option>()

            let session =
                new ASWebAuthenticationSession(
                    authorizeUrl,
                    // ASWebAuthenticationSession expects just the URL scheme here, NOT a full URL.
                    deps.Config.CallbackScheme,
                    fun callbackUrl error ->
                        if isNull error then
                            tcs.TrySetResult(Option.ofObj callbackUrl) |> ignore
                        else
                            tcs.TrySetException(new NSErrorException(error)) |> ignore)

            let presentationContext = new AuthPresentationContext(window)
            session.PresentationContextProvider <- presentationContext

            let started = session.Start()
            if not started then
                deps.Dispatch (LoginFailed "Unable to start authentication session.")
                return ()

            try
                let! callback = tcs.Task

                match callback with
                | None ->
                    deps.Dispatch (LoginFailed "Login cancelled.")
                | Some url ->
                    let uri = Uri(url.AbsoluteString)
                    let query = parseQueryParameters uri
                    let authorizationCode =
                        let mutable value = Unchecked.defaultof<string>
                        if query.TryGetValue("code", &value) then
                            Some value
                        else
                            None

                    match authorizationCode with
                    | Some code when not (String.IsNullOrWhiteSpace code) ->
                        // Exchange code for tokens
                        let! tokens =
                            exchangeAuthorizationCode deps.HttpClientFactory deps.Config codeVerifier code

                        // Attempt backend handshake (Auth0 -> Phoenix via Ueberauth)
                        let deviceId =
                            let uuid = UIDevice.CurrentDevice.IdentifierForVendor
                            if obj.ReferenceEquals(uuid, null) then Guid.NewGuid().ToString() else uuid.AsString()

                        let! mappedProfileOpt =
                            postAuth0Login deps.HttpClientFactory deps.BackendBaseUri tokens.AccessToken (Some deviceId)

                        match mappedProfileOpt with
                        | Some p -> currentProfile <- Some p
                        | None -> ()

                        // Register device (best-effort)
                        do!
                            registerDevice
                                deps.HttpClientFactory
                                deps.BackendBaseUri
                                tokens.AccessToken
                                { DeviceId = deviceId
                                  PushToken = None }

                        // Persist tokens and complete login
                        persistTokens tokens
                        deps.Dispatch (LoginSucceeded (tokens, currentProfile))
                    | _ ->
                        deps.Dispatch (LoginFailed "Authorization code missing from callback.")
            with ex ->
                deps.Dispatch (LoginFailed ex.Message)
        }
