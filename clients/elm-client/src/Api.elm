module Api exposing
    ( login
    , refresh
    , bootstrap
    , LoginResponse
    , BootstrapData
    )

{-| API client module for GlobalBridge backend.

Handles HTTP requests to authentication and data endpoints.

-}

import Auth exposing (Credentials, User)
import Http
import Json.Decode as Decode exposing (Decoder, field, string)
import Json.Encode as Encode


-- TYPES


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


type alias Thread =
    { id : String
    , name : String
    }


type alias Bridge =
    { id : String
    , platform : String
    , status : String
    }


-- API ENDPOINTS


apiUrl : String
apiUrl =
    "/api"


loginEndpoint : String
loginEndpoint =
    apiUrl ++ "/auth/login"


refreshEndpoint : String
refreshEndpoint =
    apiUrl ++ "/auth/refresh"


bootstrapEndpoint : String
bootstrapEndpoint =
    apiUrl ++ "/bootstrap"


-- HTTP REQUESTS


{-| Login with email and password
-}
login : Credentials -> (Result Http.Error LoginResponse -> msg) -> Cmd msg
login creds toMsg =
    Http.post
        { url = loginEndpoint
        , body = Http.jsonBody (encodeCredentials creds)
        , expect = Http.expectJson toMsg loginDecoder
        }


{-| Refresh access token using refresh token
-}
refresh : String -> String -> (Result Http.Error LoginResponse -> msg) -> Cmd msg
refresh refreshToken csrfToken toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.header "X-CSRF-Token" csrfToken ]
        , url = refreshEndpoint
        , body = Http.jsonBody (Encode.object [ ( "refreshToken", Encode.string refreshToken ) ])
        , expect = Http.expectJson toMsg loginDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Fetch initial application data
-}
bootstrap : String -> (Result Http.Error BootstrapData -> msg) -> Cmd msg
bootstrap authToken toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = bootstrapEndpoint
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg bootstrapDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


-- ENCODERS


encodeCredentials : Credentials -> Encode.Value
encodeCredentials creds =
    Encode.object
        [ ( "email", Encode.string creds.email )
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
    Decode.map2 Thread
        (field "id" string)
        (field "name" string)


bridgeDecoder : Decoder Bridge
bridgeDecoder =
    Decode.map3 Bridge
        (field "id" string)
        (field "platform" string)
        (field "status" string)
