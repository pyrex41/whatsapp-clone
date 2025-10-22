namespace GlobalBridge.Networking

open System
open System.Net.Http
open System.Net.Http.Headers
open System.Threading.Tasks

/// HTTP helpers for attaching a Bearer token to all outgoing requests.
module AuthHttp =

    /// Create an `HttpClient` factory that sets a Bearer token on DefaultRequestHeaders.
    /// Note: header is set once per client instance; for token refresh + retry, see task 7.4.
    let createAuthenticatedClient (tokenProvider: unit -> Task<string>) : (unit -> HttpClient) =
        fun () ->
            let client = new HttpClient()
            let token = tokenProvider().GetAwaiter().GetResult()
            if not (String.IsNullOrWhiteSpace token) then
                client.DefaultRequestHeaders.Authorization <- AuthenticationHeaderValue("Bearer", token)
            client

    /// Adapter for token providers that return ValueTask<string>.
    let createAuthenticatedClientFromValueTask (tokenProvider: unit -> ValueTask<string>) : (unit -> HttpClient) =
        let tp () = tokenProvider().AsTask()
        createAuthenticatedClient tp
