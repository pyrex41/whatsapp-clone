module State.Messages exposing
    ( Model(..)
    , Msg(..)
    , init
    , update
    , subscriptions
    , getMessages
    , isLoading
    )

{-| Message/conversation state management.

Manages messages for a specific thread, including optimistic UI updates
and real-time message delivery via Phoenix Channels.

-}

import Api exposing (ApiConfig, ApiError)
import Types exposing (Message, MessageId, ThreadId)


-- MODEL


type Model
    = NoConversation
    | Loading ThreadId
    | Ready ThreadId (List Message)
    | Error ThreadId String
    | Sending Message Model


init : Model
init =
    NoConversation


isLoading : Model -> Bool
isLoading model =
    case model of
        Loading _ ->
            True

        Sending _ _ ->
            True

        _ ->
            False


getMessages : Model -> List Message
getMessages model =
    case model of
        Ready _ messages ->
            messages

        Sending _ innerModel ->
            -- Show optimistic message while sending
            getMessages innerModel

        _ ->
            []


-- UPDATE


type Msg
    = LoadMessages ThreadId
    | MessagesLoaded ThreadId (Result ApiError (List Message))
    | SendMessage ThreadId String
    | MessageSent (Result ApiError Message)
    | NewMessageReceived Message
    | TypingIndicator ThreadId String Bool


update : ApiConfig -> String -> Msg -> Model -> ( Model, Cmd Msg )
update apiConfig authToken msg model =
    case msg of
        LoadMessages threadId ->
            ( Loading threadId
            , Api.getMessages apiConfig authToken threadId (MessagesLoaded threadId)
            )

        MessagesLoaded threadId (Ok messages) ->
            ( Ready threadId (List.sortBy .createdAt messages)
            , Cmd.none
            )

        MessagesLoaded threadId (Err error) ->
            ( Error threadId (apiErrorToString error)
            , Cmd.none
            )

        SendMessage threadId content ->
            case model of
                Ready _ messages ->
                    let
                        -- Create optimistic message (will be replaced when server responds)
                        optimisticMessage =
                            { id = "temp-" ++ String.fromInt (List.length messages)
                            , threadId = threadId
                            , content = content
                            , senderId = "current-user" -- TODO: Get from auth state
                            , senderName = "You"
                            , senderAvatar = Nothing
                            , createdAt = "" -- Will be filled by server
                            , encrypted = False
                            , bridgeOrigin = Nothing
                            , deliveryStatus = Types.Pending
                            , attachments = []
                            }
                    in
                    ( Sending optimisticMessage (Ready threadId (messages ++ [ optimisticMessage ]))
                    , Api.sendMessage apiConfig authToken threadId content MessageSent
                    )

                _ ->
                    ( model, Cmd.none )

        MessageSent (Ok message) ->
            case model of
                Sending _ (Ready threadId messages) ->
                    let
                        -- Replace optimistic message with real message
                        newMessages =
                            List.filter (\m -> not (String.startsWith "temp-" m.id)) messages
                                ++ [ message ]
                                |> List.sortBy .createdAt
                    in
                    ( Ready threadId newMessages
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        MessageSent (Err error) ->
            case model of
                Sending _ innerModel ->
                    -- Revert to previous state on error
                    case innerModel of
                        Ready threadId messages ->
                            let
                                -- Remove optimistic messages
                                realMessages =
                                    List.filter (\m -> not (String.startsWith "temp-" m.id)) messages
                            in
                            ( Error threadId (apiErrorToString error)
                            , Cmd.none
                            )

                        _ ->
                            ( innerModel, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        NewMessageReceived message ->
            case model of
                Ready threadId messages ->
                    if message.threadId == threadId then
                        ( Ready threadId (messages ++ [ message ] |> List.sortBy .createdAt)
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        TypingIndicator _ _ _ ->
            -- TODO: Implement typing indicator state
            ( model, Cmd.none )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    -- TODO: Add Phoenix Channel subscriptions for new messages
    Sub.none


-- HELPERS


apiErrorToString : ApiError -> String
apiErrorToString error =
    case error of
        Api.NetworkError ->
            "Network error sending message"

        Api.Timeout ->
            "Request timed out"

        Api.Unauthorized ->
            "Session expired"

        Api.NotFound ->
            "Thread not found"

        Api.BadStatus _ msg ->
            "Server error: " ++ msg

        Api.BadBody msg ->
            "Invalid response: " ++ msg

        Api.ServerError msg ->
            "Server error: " ++ msg
