port module Ports exposing
    ( storeSession
    , clearSession
    , onSessionRestored
    , initSocket
    , joinChannel
    , leaveChannel
    , sendChannelMessage
    , onSocketConnected
    , onChannelJoined
    , onChannelLeft
    , onChannelMessage
    , onChannelError
    , SessionData
    , ChannelConfig
    , ChannelMessage
    , ChannelError
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
