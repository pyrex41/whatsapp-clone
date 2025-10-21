module Api exposing
    ( login
    , refresh
    , bootstrap
    , getThreads
    , getThread
    , getMessages
    , sendMessage
    , LoginResponse
    , BootstrapData
    , ApiConfig
    , ApiError(..)
    , defaultConfig
    , withAuth
    )

{-| API client module for GlobalBridge backend.

Provides type-safe HTTP requests with error handling, retry logic,
and authentication integration.

-}

import Auth exposing (Credentials, User)
import Http
import Json.Decode as Decode exposing (Decoder, field, int, list, maybe, string)
import Json.Encode as Encode
import Types exposing (Attachment, AttachmentType(..), Bridge, BridgeId, BridgePlatform(..), BridgeStatus(..), DeliveryStatus(..), Message, Thread, ThreadId)


-- CONFIGURATION


type alias ApiConfig =
    { baseUrl : String
    , timeout : Maybe Float
    , apiVersion : String
    }


defaultConfig : String -> ApiConfig
defaultConfig baseUrl =
    { baseUrl = baseUrl
    , timeout = Just 10000
    , apiVersion = "v1"
    }


-- ERROR TYPES


type ApiError
    = NetworkError
    | Timeout
    | BadStatus Int String
    | BadBody String
    | Unauthorized
    | NotFound
    | ServerError String


httpErrorToApiError : Http.Error -> ApiError
httpErrorToApiError error =
    case error of
        Http.BadUrl _ ->
            BadBody "Invalid URL"

        Http.Timeout ->
            Timeout

        Http.NetworkError ->
            NetworkError

        Http.BadStatus 401 ->
            Unauthorized

        Http.BadStatus 404 ->
            NotFound

        Http.BadStatus code ->
            BadStatus code "Server error"

        Http.BadBody msg ->
            BadBody msg


-- RESPONSE TYPES


type alias LoginResponse =
    { user : User
    , accessToken : String
    , refreshToken : String
    }


type alias BootstrapData =
    { user : User
    , threads : List Thread
    , bridges : List Bridge
    , csrfToken : String
    }


-- HELPER FUNCTIONS


withAuth : String -> List Http.Header
withAuth token =
    [ Http.header "Authorization" ("Bearer " ++ token) ]


buildUrl : ApiConfig -> String -> String
buildUrl config path =
    config.baseUrl ++ "/api/" ++ config.apiVersion ++ path


-- API ENDPOINTS


loginEndpoint : ApiConfig -> String
loginEndpoint config =
    config.baseUrl ++ "/api/auth/login"


refreshEndpoint : ApiConfig -> String
refreshEndpoint config =
    config.baseUrl ++ "/api/auth/refresh"


bootstrapEndpoint : ApiConfig -> String
bootstrapEndpoint config =
    config.baseUrl ++ "/api/bootstrap"


threadsEndpoint : ApiConfig -> String
threadsEndpoint config =
    buildUrl config "/threads"


threadEndpoint : ApiConfig -> ThreadId -> String
threadEndpoint config threadId =
    buildUrl config ("/threads/" ++ threadId)


-- HTTP REQUESTS


{-| Login with email and password
-}
login : ApiConfig -> Credentials -> (Result ApiError LoginResponse -> msg) -> Cmd msg
login config creds toMsg =
    Http.post
        { url = loginEndpoint config
        , body = Http.jsonBody (encodeCredentials creds)
        , expect = Http.expectJson (toMsg << Result.mapError httpErrorToApiError) loginDecoder
        }


{-| Refresh access token using refresh token
-}
refresh : ApiConfig -> String -> String -> (Result ApiError LoginResponse -> msg) -> Cmd msg
refresh config refreshToken csrfToken toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.header "X-CSRF-Token" csrfToken ]
        , url = refreshEndpoint config
        , body = Http.jsonBody (Encode.object [ ( "refreshToken", Encode.string refreshToken ) ])
        , expect = Http.expectJson (toMsg << Result.mapError httpErrorToApiError) loginDecoder
        , timeout = config.timeout
        , tracker = Nothing
        }


{-| Fetch initial application data (bootstrap endpoint)
-}
bootstrap : ApiConfig -> String -> (Result ApiError BootstrapData -> msg) -> Cmd msg
bootstrap config authToken toMsg =
    Http.request
        { method = "GET"
        , headers = withAuth authToken
        , url = bootstrapEndpoint config
        , body = Http.emptyBody
        , expect = Http.expectJson (toMsg << Result.mapError httpErrorToApiError) bootstrapDecoder
        , timeout = config.timeout
        , tracker = Nothing
        }


{-| Get all threads for the authenticated user
-}
getThreads : ApiConfig -> String -> (Result ApiError (List Thread) -> msg) -> Cmd msg
getThreads config authToken toMsg =
    Http.request
        { method = "GET"
        , headers = withAuth authToken
        , url = threadsEndpoint config
        , body = Http.emptyBody
        , expect = Http.expectJson (toMsg << Result.mapError httpErrorToApiError) (Decode.list threadDecoder)
        , timeout = config.timeout
        , tracker = Nothing
        }


{-| Get a specific thread by ID
-}
getThread : ApiConfig -> String -> ThreadId -> (Result ApiError Thread -> msg) -> Cmd msg
getThread config authToken threadId toMsg =
    Http.request
        { method = "GET"
        , headers = withAuth authToken
        , url = threadEndpoint config threadId
        , body = Http.emptyBody
        , expect = Http.expectJson (toMsg << Result.mapError httpErrorToApiError) threadDecoder
        , timeout = config.timeout
        , tracker = Nothing
        }


{-| Get all messages for a specific thread
-}
getMessages : ApiConfig -> String -> ThreadId -> (Result ApiError (List Message) -> msg) -> Cmd msg
getMessages config authToken threadId toMsg =
    Http.request
        { method = "GET"
        , headers = withAuth authToken
        , url = threadEndpoint config threadId ++ "/messages"
        , body = Http.emptyBody
        , expect = Http.expectJson (toMsg << Result.mapError httpErrorToApiError) (list messageDecoder)
        , timeout = config.timeout
        , tracker = Nothing
        }


{-| Send a message to a thread
-}
sendMessage : ApiConfig -> String -> ThreadId -> String -> (Result ApiError Message -> msg) -> Cmd msg
sendMessage config authToken threadId content toMsg =
    Http.request
        { method = "POST"
        , headers = withAuth authToken
        , url = threadEndpoint config threadId ++ "/messages"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "content", Encode.string content )
                    ]
                )
        , expect = Http.expectJson (toMsg << Result.mapError httpErrorToApiError) messageDecoder
        , timeout = config.timeout
        , tracker = Nothing
        }


-- ENCODERS


encodeCredentials : Credentials -> Encode.Value
encodeCredentials creds =
    Encode.object
        [ ( "identifier", Encode.string creds.email )
        , ( "password", Encode.string creds.password )
        ]


-- DECODERS


loginDecoder : Decoder LoginResponse
loginDecoder =
    Decode.map3 LoginResponse
        (field "user" userDecoder)
        (field "access_token" string)
        (field "refresh_token" string)


userDecoder : Decoder User
userDecoder =
    Decode.map3 User
        (field "id" string)
        (field "email" string)
        (field "created_at" string)


bootstrapDecoder : Decoder BootstrapData
bootstrapDecoder =
    Decode.map4 BootstrapData
        (field "user" userDecoder)
        (field "threads" (Decode.list threadDecoder))
        (field "bridges" (Decode.list bridgeDecoder))
        (field "csrf_token" string)


threadDecoder : Decoder Thread
threadDecoder =
    Decode.map7 Thread
        (field "id" string)
        (field "name" string)
        (maybe (field "last_message" messageDecoder))
        (Decode.oneOf [ field "unread_count" Decode.int, Decode.succeed 0 ])
        (maybe (field "bridge" bridgeDecoder))
        (field "created_at" string)
        (field "updated_at" string)


messageDecoder : Decoder Message
messageDecoder =
    Decode.succeed Message
        |> andMap (field "id" string)
        |> andMap (field "thread_id" string)
        |> andMap (field "content" string)
        |> andMap (field "sender_id" string)
        |> andMap (field "sender_name" string)
        |> andMap (maybe (field "sender_avatar" string))
        |> andMap (field "created_at" string)
        |> andMap (Decode.oneOf [ field "encrypted" Decode.bool, Decode.succeed False ])
        |> andMap (maybe (field "bridge_origin" string))
        |> andMap (Decode.oneOf [ field "delivery_status" deliveryStatusDecoder, Decode.succeed Sent ])
        |> andMap (Decode.oneOf [ field "attachments" (list attachmentDecoder), Decode.succeed [] ])


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


bridgeDecoder : Decoder Bridge
bridgeDecoder =
    Decode.map7 Bridge
        (field "id" string)
        (field "thread_id" string)
        (field "platform" platformDecoder)
        (field "status" statusDecoder)
        (field "config" bridgeConfigDecoder)
        (maybe (field "last_sync_at" string))
        (maybe (field "error_message" string))


platformDecoder : Decoder BridgePlatform
platformDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case String.toLower str of
                    "slack" ->
                        Decode.succeed Slack

                    "telegram" ->
                        Decode.succeed Telegram

                    "whatsapp" ->
                        Decode.succeed WhatsApp

                    _ ->
                        Decode.fail ("Unknown platform: " ++ str)
            )


statusDecoder : Decoder BridgeStatus
statusDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case String.toLower str of
                    "connected" ->
                        Decode.succeed Connected

                    "syncing" ->
                        Decode.succeed Syncing

                    "disconnected" ->
                        Decode.succeed Disconnected

                    "error" ->
                        Decode.succeed Error

                    _ ->
                        Decode.succeed Disconnected
            )


bridgeConfigDecoder : Decoder Types.BridgeConfig
bridgeConfigDecoder =
    Decode.map2 Types.BridgeConfig
        (maybe (field "channel_id" string))
        (maybe (field "channel_name" string))


deliveryStatusDecoder : Decoder DeliveryStatus
deliveryStatusDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case String.toLower str of
                    "pending" ->
                        Decode.succeed Pending

                    "sent" ->
                        Decode.succeed Sent

                    "delivered" ->
                        Decode.succeed Delivered

                    "read" ->
                        Decode.succeed Read

                    "failed" ->
                        Decode.succeed Failed

                    _ ->
                        Decode.succeed Sent
            )


attachmentTypeDecoder : Decoder AttachmentType
attachmentTypeDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case String.toLower str of
                    "image" ->
                        Decode.succeed Image

                    "video" ->
                        Decode.succeed Video

                    "audio" ->
                        Decode.succeed Audio

                    "document" ->
                        Decode.succeed Document

                    _ ->
                        Decode.succeed Other
            )


attachmentDecoder : Decoder Attachment
attachmentDecoder =
    Decode.map6 Attachment
        (field "id" string)
        (field "type" attachmentTypeDecoder)
        (field "file_name" string)
        (field "file_size" int)
        (field "url" string)
        (maybe (field "thumbnail_url" string))
