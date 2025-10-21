module State.Bridges exposing
    ( Model
    , Msg(..)
    , init
    , update
    , subscriptions
    , getBridges
    , getBridgeForThread
    )

{-| Bridge status state management.

Manages bridge connections, sync status, and real-time bridge events.

-}

import Types exposing (Bridge, BridgeId, BridgeStatus, ThreadId)


-- MODEL


type Model
    = NotLoaded
    | Loading
    | Ready (List Bridge)
    | Error String


init : Model
init =
    NotLoaded


getBridges : Model -> List Bridge
getBridges model =
    case model of
        Ready bridges ->
            bridges

        _ ->
            []


getBridgeForThread : ThreadId -> Model -> Maybe Bridge
getBridgeForThread threadId model =
    case model of
        Ready bridges ->
            List.filter (\b -> b.threadId == threadId) bridges
                |> List.head

        _ ->
            Nothing


-- UPDATE


type Msg
    = LoadBridges (List Bridge)
    | BridgeStatusChanged BridgeId BridgeStatus
    | BridgeSyncCompleted BridgeId
    | BridgeError BridgeId String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LoadBridges bridges ->
            ( Ready bridges
            , Cmd.none
            )

        BridgeStatusChanged bridgeId status ->
            case model of
                Ready bridges ->
                    let
                        updatedBridges =
                            List.map
                                (\b ->
                                    if b.id == bridgeId then
                                        { b | status = status }

                                    else
                                        b
                                )
                                bridges
                    in
                    ( Ready updatedBridges
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        BridgeSyncCompleted bridgeId ->
            case model of
                Ready bridges ->
                    let
                        updatedBridges =
                            List.map
                                (\b ->
                                    if b.id == bridgeId then
                                        { b
                                            | status = Types.Connected
                                            , lastSyncAt = Just "" -- TODO: Use actual timestamp
                                        }

                                    else
                                        b
                                )
                                bridges
                    in
                    ( Ready updatedBridges
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        BridgeError bridgeId errorMsg ->
            case model of
                Ready bridges ->
                    let
                        updatedBridges =
                            List.map
                                (\b ->
                                    if b.id == bridgeId then
                                        { b
                                            | status = Types.Error
                                            , errorMessage = Just errorMsg
                                        }

                                    else
                                        b
                                )
                                bridges
                    in
                    ( Ready updatedBridges
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    -- TODO: Add Phoenix Channel subscriptions for bridge events
    Sub.none
