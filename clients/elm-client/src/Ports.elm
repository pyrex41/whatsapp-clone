port module Ports exposing
    ( ChannelConfig
    , ChannelError
    , ChannelMessage
    , SessionData
    , auth0Login
    , auth0Logout
    , clearSession
    , initSocket
    , joinChannel
    , leaveChannel
    , onAuth0LoginComplete
    , onAuth0LoginError
    , onChannelError
    , onChannelJoined
    , onChannelLeft
    , onChannelMessage
    , onSessionRestored
    , onSocketConnected
    , sendChannelMessage
    , storeSession
    )

{-| JavaScript interop ports for session management and Phoenix Channels.

Handles token storage, WebSocket connections, and real-time messaging.

-}

import Json.Decode as Decode
import Json.Encode as Encode



-- TYPES


type alias SessionData =
    { accessToken : String
    , refreshToken : String
    , userId : String
    , username : String
    , email : String
    }


type alias ChannelConfig =
    { topic : String
    , params : Encode.Value
    }


type alias ChannelMessage =
    { topic : String
    , event : String
    , payload : Encode.Value
    }


type alias ChannelError =
    { topic : String
    , error : String
    }



-- SESSION PORTS (Outbound: Elm -> JavaScript)


{-| Store authentication session in browser storage
-}
port storeSession : SessionData -> Cmd msg


{-| Clear stored session data
-}
port clearSession : () -> Cmd msg



-- SESSION PORTS (Inbound: JavaScript -> Elm)


{-| Receive restored session data on app startup
-}
port onSessionRestored : (Maybe SessionData -> msg) -> Sub msg



-- PHOENIX CHANNELS PORTS (Outbound: Elm -> JavaScript)


{-| Initialize Phoenix Socket with endpoint and auth token
-}
port initSocket : { endpoint : String, token : String } -> Cmd msg


{-| Join a Phoenix Channel with topic and params
-}
port joinChannel : ChannelConfig -> Cmd msg


{-| Leave a Phoenix Channel by topic
-}
port leaveChannel : String -> Cmd msg


{-| Send message to a channel
-}
port sendChannelMessage : { topic : String, event : String, payload : Encode.Value } -> Cmd msg



-- PHOENIX CHANNELS PORTS (Inbound: JavaScript -> Elm)


{-| Socket connection status changed
-}
port onSocketConnected : (Bool -> msg) -> Sub msg


{-| Successfully joined a channel
-}
port onChannelJoined : ({ topic : String, data : Encode.Value } -> msg) -> Sub msg


{-| Left a channel
-}
port onChannelLeft : (String -> msg) -> Sub msg


{-| Received message from a channel
-}
port onChannelMessage : (ChannelMessage -> msg) -> Sub msg


{-| Channel error occurred
-}
port onChannelError : (ChannelError -> msg) -> Sub msg



-- AUTH0 PORTS (Outbound: Elm -> JavaScript)


{-| Trigger Auth0 login flow
-}
port auth0Login : () -> Cmd msg


{-| Trigger Auth0 logout
-}
port auth0Logout : () -> Cmd msg



-- AUTH0 PORTS (Inbound: JavaScript -> Elm)


{-| Auth0 login completed successfully with session data
-}
port onAuth0LoginComplete : (SessionData -> msg) -> Sub msg


{-| Auth0 login failed with error message
-}
port onAuth0LoginError : (String -> msg) -> Sub msg
