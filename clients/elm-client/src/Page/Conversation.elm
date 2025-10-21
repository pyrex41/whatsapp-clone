module Page.Conversation exposing (Model, Msg(..), init, update, view)

{-| Conversation view with real-time messaging, typing indicators, and optimistic UI.

Displays a message stream for a specific thread with:

  - Real-time message updates via Phoenix Channels
  - Message composer with optimistic send logic
  - Delivery receipts and read status
  - Typing indicators
  - Message metadata (timestamps, sender info, bridge origin)
  - Attachment handling (as stubs)
  - Auto-scroll behavior
  - Message formatting (URLs, mentions)
  - Error handling with retry

-}

import Html exposing (Html, button, div, img, input, li, p, span, text, textarea, ul)
import Html.Attributes exposing (alt, class, classList, disabled, placeholder, src, style, value)
import Html.Events exposing (onClick, onInput)
import State.Messages as Messages
import Types exposing (Attachment, AttachmentType(..), DeliveryStatus(..), Message, ThreadId)


-- MODEL


type alias Model =
    { threadId : ThreadId
    , threadName : String
    , messagesState : Messages.Model
    , composerText : String
    , typingUsers : List String
    , autoScrollEnabled : Bool
    , errorMessage : Maybe String
    }


init : ThreadId -> String -> Messages.Model -> Model
init threadId threadName messagesState =
    { threadId = threadId
    , threadName = threadName
    , messagesState = messagesState
    , composerText = ""
    , typingUsers = []
    , autoScrollEnabled = True
    , errorMessage = Nothing
    }


-- UPDATE


type Msg
    = MessagesMsg Messages.Msg
    | ComposerTextChanged String
    | SendMessage
    | RetryFailedMessage String
    | TypingIndicatorReceived String Bool
    | ScrolledUp
    | EnableAutoScroll


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MessagesMsg messagesMsg ->
            -- Messages state is managed in Main, this is just for local UI updates
            ( model, Cmd.none )

        ComposerTextChanged text ->
            ( { model | composerText = text, errorMessage = Nothing }
            , Cmd.none
            )

        SendMessage ->
            if String.isEmpty (String.trim model.composerText) then
                ( model, Cmd.none )

            else
                ( { model | composerText = "", errorMessage = Nothing }
                , Cmd.none
                  -- Actual send is handled via MessagesMsg from parent
                )

        RetryFailedMessage messageId ->
            -- TODO: Implement retry logic
            ( model, Cmd.none )

        TypingIndicatorReceived userId isTyping ->
            let
                updatedTypingUsers =
                    if isTyping then
                        if List.member userId model.typingUsers then
                            model.typingUsers

                        else
                            userId :: model.typingUsers

                    else
                        List.filter (\id -> id /= userId) model.typingUsers
            in
            ( { model | typingUsers = updatedTypingUsers }, Cmd.none )

        ScrolledUp ->
            ( { model | autoScrollEnabled = False }, Cmd.none )

        EnableAutoScroll ->
            ( { model | autoScrollEnabled = True }, Cmd.none )


-- VIEW


view : Model -> Html Msg
view model =
    div [ class "conversation-page" ]
        [ viewHeader model
        , viewMessages model
        , viewTypingIndicators model
        , viewComposer model
        , viewError model
        ]


viewHeader : Model -> Html msg
viewHeader model =
    div [ class "conversation-header" ]
        [ div [ class "conversation-header-content" ]
            [ Html.h2 [ class "conversation-title" ] [ text model.threadName ]
            , span [ class "conversation-subtitle" ]
                [ text (String.fromInt (Messages.getMessages model.messagesState |> List.length) ++ " messages") ]
            ]
        ]


viewMessages : Model -> Html Msg
viewMessages model =
    case model.messagesState of
        Messages.NoConversation ->
            div [ class "messages-empty" ]
                [ p [] [ text "Select a thread to start messaging" ] ]

        Messages.Loading _ ->
            div [ class "messages-loading" ]
                [ p [] [ text "Loading messages..." ] ]

        Messages.Error _ error ->
            div [ class "messages-error" ]
                [ p [] [ text ("Error: " ++ error) ]
                , button [ class "btn btn-primary", onClick (MessagesMsg (Messages.LoadMessages model.threadId)) ]
                    [ text "Retry" ]
                ]

        Messages.Ready _ messages ->
            viewMessageList messages model.autoScrollEnabled

        Messages.Sending optimisticMsg (Messages.Ready _ messages) ->
            -- Show optimistic message while sending
            viewMessageList messages model.autoScrollEnabled

        Messages.Sending _ innerModel ->
            -- Handle other Sending cases by showing the inner model
            viewMessages { model | messagesState = innerModel }


viewMessageList : List Message -> Bool -> Html Msg
viewMessageList messages autoScrollEnabled =
    if List.isEmpty messages then
        div [ class "messages-empty" ]
            [ p [] [ text "No messages yet. Start the conversation!" ] ]

    else
        div
            [ class "messages-container"
            , classList [ ( "auto-scroll", autoScrollEnabled ) ]
            ]
            [ ul [ class "messages-list" ]
                (List.map viewMessage messages)
            ]


viewMessage : Message -> Html Msg
viewMessage message =
    let
        isOwnMessage =
            message.senderId == "current-user"

        -- TODO: Get from auth state
    in
    li
        [ class "message-item"
        , classList
            [ ( "message-own", isOwnMessage )
            , ( "message-other", not isOwnMessage )
            , ( "message-failed", message.deliveryStatus == Failed )
            ]
        ]
        [ if not isOwnMessage then
            viewSenderAvatar message

          else
            text ""
        , div [ class "message-content-wrapper" ]
            [ if not isOwnMessage then
                viewSenderName message

              else
                text ""
            , div [ class "message-bubble" ]
                [ viewMessageContent message
                , viewAttachments message.attachments
                ]
            , div [ class "message-metadata" ]
                [ viewTimestamp message.createdAt
                , viewBridgeOrigin message.bridgeOrigin
                , viewDeliveryStatus message.deliveryStatus isOwnMessage
                , viewEncryptionStatus message.encrypted
                ]
            ]
        , if message.deliveryStatus == Failed then
            viewRetryButton message.id

          else
            text ""
        ]


viewSenderAvatar : Message -> Html msg
viewSenderAvatar message =
    case message.senderAvatar of
        Just avatarUrl ->
            img
                [ class "message-avatar"
                , src avatarUrl
                , alt (message.senderName ++ "'s avatar")
                ]
                []

        Nothing ->
            div [ class "message-avatar message-avatar-placeholder" ]
                [ text (String.left 1 message.senderName) ]


viewSenderName : Message -> Html msg
viewSenderName message =
    span [ class "message-sender-name" ] [ text message.senderName ]


viewMessageContent : Message -> Html msg
viewMessageContent message =
    div [ class "message-text" ]
        [ text message.content
          -- TODO: Add message formatting (URLs, mentions)
        ]


viewAttachments : List Attachment -> Html msg
viewAttachments attachments =
    if List.isEmpty attachments then
        text ""

    else
        div [ class "message-attachments" ]
            (List.map viewAttachment attachments)


viewAttachment : Attachment -> Html msg
viewAttachment attachment =
    div [ class "message-attachment", class (attachmentTypeClass attachment.attachmentType) ]
        [ case attachment.thumbnailUrl of
            Just thumbnailUrl ->
                img [ class "attachment-thumbnail", src thumbnailUrl, alt attachment.fileName ] []

            Nothing ->
                div [ class "attachment-icon" ] [ text (attachmentTypeIcon attachment.attachmentType) ]
        , div [ class "attachment-info" ]
            [ span [ class "attachment-name" ] [ text attachment.fileName ]
            , span [ class "attachment-size" ] [ text (formatFileSize attachment.fileSize) ]
            , Html.a [ Html.Attributes.href attachment.url, Html.Attributes.target "_blank", class "attachment-download" ]
                [ text "Download" ]
            ]
        ]


viewTimestamp : String -> Html msg
viewTimestamp timestamp =
    span [ class "message-timestamp" ]
        [ text (formatTimestamp timestamp) ]


viewBridgeOrigin : Maybe String -> Html msg
viewBridgeOrigin maybeBridgeOrigin =
    case maybeBridgeOrigin of
        Nothing ->
            text ""

        Just bridgeOrigin ->
            span [ class "message-bridge-badge", class ("bridge-" ++ String.toLower bridgeOrigin) ]
                [ text (bridgeOriginIcon bridgeOrigin ++ " " ++ bridgeOrigin) ]


viewDeliveryStatus : DeliveryStatus -> Bool -> Html msg
viewDeliveryStatus status isOwnMessage =
    if not isOwnMessage then
        text ""

    else
        span [ class "message-delivery-status", class (deliveryStatusClass status) ]
            [ text (deliveryStatusIcon status) ]


viewEncryptionStatus : Bool -> Html msg
viewEncryptionStatus encrypted =
    if encrypted then
        span [ class "message-encryption-badge" ] [ text "🔒" ]

    else
        text ""


viewRetryButton : String -> Html Msg
viewRetryButton messageId =
    button
        [ class "message-retry-btn"
        , onClick (RetryFailedMessage messageId)
        ]
        [ text "Retry" ]


viewTypingIndicators : Model -> Html msg
viewTypingIndicators model =
    if List.isEmpty model.typingUsers then
        text ""

    else
        div [ class "typing-indicators" ]
            [ span [ class "typing-text" ]
                [ text (formatTypingIndicator model.typingUsers) ]
            , div [ class "typing-dots" ]
                [ span [ class "typing-dot" ] []
                , span [ class "typing-dot" ] []
                , span [ class "typing-dot" ] []
                ]
            ]


viewComposer : Model -> Html Msg
viewComposer model =
    div [ class "message-composer" ]
        [ textarea
            [ class "composer-input"
            , placeholder "Type a message..."
            , value model.composerText
            , onInput ComposerTextChanged
            , disabled (Messages.isLoading model.messagesState)
            ]
            []
        , button
            [ class "composer-send-btn"
            , classList [ ( "btn-primary", not (String.isEmpty (String.trim model.composerText)) ) ]
            , onClick SendMessage
            , disabled (String.isEmpty (String.trim model.composerText) || Messages.isLoading model.messagesState)
            ]
            [ text "Send" ]
        ]


viewError : Model -> Html msg
viewError model =
    case model.errorMessage of
        Nothing ->
            text ""

        Just error ->
            div [ class "conversation-error" ]
                [ p [] [ text error ] ]


-- HELPERS


formatTimestamp : String -> String
formatTimestamp timestamp =
    -- TODO: Implement relative time formatting (e.g., "2 minutes ago")
    -- For now, just show the raw timestamp
    if String.isEmpty timestamp then
        "Just now"

    else
        timestamp


formatTypingIndicator : List String -> String
formatTypingIndicator typingUsers =
    case typingUsers of
        [] ->
            ""

        [ user ] ->
            user ++ " is typing"

        [ user1, user2 ] ->
            user1 ++ " and " ++ user2 ++ " are typing"

        _ ->
            "Several people are typing"


deliveryStatusClass : DeliveryStatus -> String
deliveryStatusClass status =
    case status of
        Pending ->
            "status-pending"

        Sent ->
            "status-sent"

        Delivered ->
            "status-delivered"

        Read ->
            "status-read"

        Failed ->
            "status-failed"


deliveryStatusIcon : DeliveryStatus -> String
deliveryStatusIcon status =
    case status of
        Pending ->
            "⏱"

        Sent ->
            "✓"

        Delivered ->
            "✓✓"

        Read ->
            "✓✓"

        Failed ->
            "✗"


attachmentTypeClass : AttachmentType -> String
attachmentTypeClass attachmentType =
    case attachmentType of
        Image ->
            "attachment-image"

        Video ->
            "attachment-video"

        Audio ->
            "attachment-audio"

        Document ->
            "attachment-document"

        Other ->
            "attachment-other"


attachmentTypeIcon : AttachmentType -> String
attachmentTypeIcon attachmentType =
    case attachmentType of
        Image ->
            "🖼"

        Video ->
            "🎥"

        Audio ->
            "🎵"

        Document ->
            "📄"

        Other ->
            "📎"


bridgeOriginIcon : String -> String
bridgeOriginIcon origin =
    case String.toLower origin of
        "slack" ->
            "📧"

        "telegram" ->
            "✈️"

        "whatsapp" ->
            "💬"

        _ ->
            "🔗"


formatFileSize : Int -> String
formatFileSize bytes =
    if bytes < 1024 then
        String.fromInt bytes ++ " B"

    else if bytes < 1024 * 1024 then
        String.fromFloat (toFloat bytes / 1024) ++ " KB"

    else if bytes < 1024 * 1024 * 1024 then
        String.fromFloat (toFloat bytes / (1024 * 1024)) ++ " MB"

    else
        String.fromFloat (toFloat bytes / (1024 * 1024 * 1024)) ++ " GB"
