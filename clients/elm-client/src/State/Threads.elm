module State.Threads exposing
    ( Model(..)
    , Msg(..)
    , init
    , update
    , subscriptions
    , isLoading
    , getThreads
    )

{-| Thread list state management.

Manages the list of threads, loading states, and real-time updates via Phoenix Channels.

-}

import Api exposing (ApiConfig, ApiError)
import Ports
import Types exposing (Thread, ThreadId)


-- MODEL


type Model
    = NotLoaded
    | Loading
    | Ready (List Thread)
    | Error String


init : Model
init =
    NotLoaded


isLoading : Model -> Bool
isLoading model =
    case model of
        Loading ->
            True

        _ ->
            False


getThreads : Model -> List Thread
getThreads model =
    case model of
        Ready threads ->
            threads

        _ ->
            []


-- UPDATE


type Msg
    = LoadThreads
    | ThreadsLoaded (Result ApiError (List Thread))
    | ThreadUpdated Thread
    | NewThread Thread
    | ThreadDeleted ThreadId


update : ApiConfig -> String -> Msg -> Model -> ( Model, Cmd Msg )
update apiConfig authToken msg model =
    case msg of
        LoadThreads ->
            ( Loading
            , Api.getThreads apiConfig authToken ThreadsLoaded
            )

        ThreadsLoaded (Ok threads) ->
            ( Ready threads
            , Cmd.none
            )

        ThreadsLoaded (Err error) ->
            ( Error (apiErrorToString error)
            , Cmd.none
            )

        ThreadUpdated updatedThread ->
            case model of
                Ready threads ->
                    let
                        newThreads =
                            List.map
                                (\t ->
                                    if t.id == updatedThread.id then
                                        updatedThread

                                    else
                                        t
                                )
                                threads
                    in
                    ( Ready newThreads
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        NewThread thread ->
            case model of
                Ready threads ->
                    ( Ready (thread :: threads)
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ThreadDeleted threadId ->
            case model of
                Ready threads ->
                    let
                        newThreads =
                            List.filter (\t -> t.id /= threadId) threads
                    in
                    ( Ready newThreads
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    -- TODO: Add Phoenix Channel subscriptions for thread updates
    Sub.none


-- HELPERS


apiErrorToString : ApiError -> String
apiErrorToString error =
    case error of
        Api.NetworkError ->
            "Network error loading threads"

        Api.Timeout ->
            "Request timed out"

        Api.Unauthorized ->
            "Session expired"

        Api.NotFound ->
            "Threads endpoint not found"

        Api.BadStatus _ msg ->
            "Server error: " ++ msg

        Api.BadBody msg ->
            "Invalid response: " ++ msg

        Api.ServerError msg ->
            "Server error: " ++ msg
