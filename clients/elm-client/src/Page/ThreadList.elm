module Page.ThreadList exposing (Model, Msg(..), init, update, view)

{-| Thread list page with search, filtering, and real-time updates.

Displays all threads with unread counts, bridge status, and allows
thread creation and navigation.

-}

import Html exposing (Html, button, div, h2, input, li, p, span, text, ul)
import Html.Attributes exposing (class, classList, disabled, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import State.Threads as Threads
import Types exposing (Bridge, BridgePlatform(..), BridgeStatus(..), Thread, ThreadId)


-- MODEL


type alias Model =
    { threadsState : Threads.Model
    , searchQuery : String
    , filterBridgeType : Maybe BridgePlatform
    , selectedThreadId : Maybe ThreadId
    , showCreateForm : Bool
    , createFormName : String
    , createFormError : Maybe String
    }


init : Threads.Model -> Model
init threadsState =
    { threadsState = threadsState
    , searchQuery = ""
    , filterBridgeType = Nothing
    , selectedThreadId = Nothing
    , showCreateForm = False
    , createFormName = ""
    , createFormError = Nothing
    }


-- UPDATE


type Msg
    = ThreadsMsg Threads.Msg
    | SearchQueryChanged String
    | FilterByBridgeType (Maybe BridgePlatform)
    | SelectThread ThreadId
    | ShowCreateForm
    | HideCreateForm
    | CreateFormNameChanged String
    | SubmitCreateThread
    | KeyboardNavigation String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ThreadsMsg threadsMsg ->
            -- Threads state is managed in Main, this is just for view updates
            ( model, Cmd.none )

        SearchQueryChanged query ->
            ( { model | searchQuery = query, selectedThreadId = Nothing }
            , Cmd.none
            )

        FilterByBridgeType bridgeType ->
            ( { model | filterBridgeType = bridgeType, selectedThreadId = Nothing }
            , Cmd.none
            )

        SelectThread threadId ->
            ( { model | selectedThreadId = Just threadId }
            , Cmd.none
            )

        ShowCreateForm ->
            ( { model
                | showCreateForm = True
                , createFormName = ""
                , createFormError = Nothing
              }
            , Cmd.none
            )

        HideCreateForm ->
            ( { model | showCreateForm = False, createFormName = "", createFormError = Nothing }
            , Cmd.none
            )

        CreateFormNameChanged name ->
            ( { model | createFormName = name, createFormError = Nothing }
            , Cmd.none
            )

        SubmitCreateThread ->
            case validateThreadName model.createFormName of
                Ok _ ->
                    -- TODO: Implement thread creation API call
                    ( { model | showCreateForm = False, createFormName = "" }
                    , Cmd.none
                    )

                Err error ->
                    ( { model | createFormError = Just error }
                    , Cmd.none
                    )

        KeyboardNavigation key ->
            case key of
                "ArrowDown" ->
                    ( selectNextThread model, Cmd.none )

                "ArrowUp" ->
                    ( selectPreviousThread model, Cmd.none )

                "Enter" ->
                    -- TODO: Navigate to selected thread
                    ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )


-- VIEW


view : Model -> Html Msg
view model =
    div [ class "thread-list-page" ]
        [ viewHeader
        , viewSearchBar model
        , viewFilters model
        , viewThreads model
        , if model.showCreateForm then
            viewCreateForm model

          else
            text ""
        ]


viewHeader : Html Msg
viewHeader =
    div [ class "thread-list-header" ]
        [ h2 [ class "thread-list-title" ] [ text "Conversations" ]
        , button [ class "btn btn-primary", onClick ShowCreateForm ]
            [ text "+ New Thread" ]
        ]


viewSearchBar : Model -> Html Msg
viewSearchBar model =
    div [ class "search-bar" ]
        [ input
            [ type_ "text"
            , class "search-input"
            , placeholder "Search threads..."
            , value model.searchQuery
            , onInput SearchQueryChanged
            ]
            []
        ]


viewFilters : Model -> Html Msg
viewFilters model =
    div [ class "thread-filters" ]
        [ button
            [ class "filter-btn"
            , classList [ ( "active", model.filterBridgeType == Nothing ) ]
            , onClick (FilterByBridgeType Nothing)
            ]
            [ text "All" ]
        , button
            [ class "filter-btn"
            , classList [ ( "active", model.filterBridgeType == Just Slack ) ]
            , onClick (FilterByBridgeType (Just Slack))
            ]
            [ text "📧 Slack" ]
        , button
            [ class "filter-btn"
            , classList [ ( "active", model.filterBridgeType == Just Telegram ) ]
            , onClick (FilterByBridgeType (Just Telegram))
            ]
            [ text "✈️ Telegram" ]
        , button
            [ class "filter-btn"
            , classList [ ( "active", model.filterBridgeType == Just WhatsApp ) ]
            , onClick (FilterByBridgeType (Just WhatsApp))
            ]
            [ text "💬 WhatsApp" ]
        ]


viewThreads : Model -> Html Msg
viewThreads model =
    case model.threadsState of
        Threads.NotLoaded ->
            div [ class "thread-list-empty" ]
                [ p [] [ text "Threads not loaded" ] ]

        Threads.Loading ->
            div [ class "thread-list-loading" ]
                [ p [] [ text "Loading threads..." ] ]

        Threads.Error err ->
            div [ class "thread-list-error" ]
                [ p [] [ text ("Error: " ++ err) ] ]

        Threads.Ready threads ->
            let
                filteredThreads =
                    threads
                        |> filterBySearch model.searchQuery
                        |> filterByBridgeType model.filterBridgeType
            in
            if List.isEmpty filteredThreads then
                div [ class "thread-list-empty" ]
                    [ p [] [ text "No threads found" ]
                    , if model.searchQuery /= "" || model.filterBridgeType /= Nothing then
                        p [ class "text-muted" ] [ text "Try adjusting your filters" ]

                      else
                        button [ class "btn btn-primary", onClick ShowCreateForm ]
                            [ text "Create your first thread" ]
                    ]

            else
                ul [ class "thread-list" ]
                    (List.map (viewThread model.selectedThreadId) filteredThreads)


viewThread : Maybe ThreadId -> Thread -> Html Msg
viewThread selectedId thread =
    let
        isSelected =
            selectedId == Just thread.id
    in
    li
        [ class "thread-item"
        , classList [ ( "selected", isSelected ) ]
        , onClick (SelectThread thread.id)
        ]
        [ div [ class "thread-content" ]
            [ div [ class "thread-header" ]
                [ span [ class "thread-name" ] [ text thread.name ]
                , viewBridgeBadge thread.bridge
                ]
            , div [ class "thread-meta" ]
                [ viewLastMessage thread.lastMessage
                , viewUnreadCount thread.unreadCount
                ]
            , viewBridgeStatus thread.bridge
            ]
        ]


viewBridgeBadge : Maybe Bridge -> Html msg
viewBridgeBadge maybeBridge =
    case maybeBridge of
        Nothing ->
            text ""

        Just bridge ->
            span [ class "bridge-badge", class (bridgePlatformClass bridge.platform) ]
                [ text (bridgePlatformIcon bridge.platform ++ " " ++ bridgePlatformName bridge.platform) ]


viewLastMessage : Maybe Types.Message -> Html msg
viewLastMessage maybeMessage =
    case maybeMessage of
        Nothing ->
            span [ class "last-message text-muted" ] [ text "No messages yet" ]

        Just message ->
            span [ class "last-message" ] [ text (truncate 50 message.content) ]


viewUnreadCount : Int -> Html msg
viewUnreadCount count =
    if count > 0 then
        span [ class "unread-badge" ] [ text (String.fromInt count) ]

    else
        text ""


viewBridgeStatus : Maybe Bridge -> Html msg
viewBridgeStatus maybeBridge =
    case maybeBridge of
        Nothing ->
            text ""

        Just bridge ->
            div [ class "bridge-status" ]
                [ span
                    [ class "status-indicator"
                    , class (bridgeStatusClass bridge.status)
                    ]
                    []
                , span [ class "status-text" ]
                    [ text (bridgeStatusText bridge.status) ]
                ]


viewCreateForm : Model -> Html Msg
viewCreateForm model =
    div [ class "modal-overlay", onClick HideCreateForm ]
        [ div [ class "modal-content" ]
            [ h2 [] [ text "Create New Thread" ]
            , div [ class "form-group" ]
                [ Html.label [ class "form-label" ] [ text "Thread Name" ]
                , input
                    [ type_ "text"
                    , class "form-input"
                    , placeholder "e.g., Team Chat"
                    , value model.createFormName
                    , onInput CreateFormNameChanged
                    ]
                    []
                , case model.createFormError of
                    Just error ->
                        p [ class "form-error" ] [ text error ]

                    Nothing ->
                        text ""
                ]
            , div [ class "modal-actions" ]
                [ button [ class "btn btn-secondary", onClick HideCreateForm ]
                    [ text "Cancel" ]
                , button
                    [ class "btn btn-primary"
                    , onClick SubmitCreateThread
                    , disabled (String.isEmpty model.createFormName)
                    ]
                    [ text "Create Thread" ]
                ]
            ]
        ]


-- HELPERS


filterBySearch : String -> List Thread -> List Thread
filterBySearch query threads =
    if String.isEmpty query then
        threads

    else
        let
            lowerQuery =
                String.toLower query
        in
        List.filter
            (\thread ->
                String.contains lowerQuery (String.toLower thread.name)
            )
            threads


filterByBridgeType : Maybe BridgePlatform -> List Thread -> List Thread
filterByBridgeType maybePlatform threads =
    case maybePlatform of
        Nothing ->
            threads

        Just platform ->
            List.filter
                (\thread ->
                    case thread.bridge of
                        Nothing ->
                            False

                        Just bridge ->
                            bridge.platform == platform
                )
                threads


selectNextThread : Model -> Model
selectNextThread model =
    case model.threadsState of
        Threads.Ready threads ->
            let
                filteredThreads =
                    threads
                        |> filterBySearch model.searchQuery
                        |> filterByBridgeType model.filterBridgeType

                currentIndex =
                    case model.selectedThreadId of
                        Nothing ->
                            -1

                        Just threadId ->
                            List.indexedMap Tuple.pair filteredThreads
                                |> List.filter (\( _, t ) -> t.id == threadId)
                                |> List.head
                                |> Maybe.map Tuple.first
                                |> Maybe.withDefault -1

                nextIndex =
                    min (currentIndex + 1) (List.length filteredThreads - 1)

                nextThread =
                    List.drop nextIndex filteredThreads
                        |> List.head
            in
            { model | selectedThreadId = Maybe.map .id nextThread }

        _ ->
            model


selectPreviousThread : Model -> Model
selectPreviousThread model =
    case model.threadsState of
        Threads.Ready threads ->
            let
                filteredThreads =
                    threads
                        |> filterBySearch model.searchQuery
                        |> filterByBridgeType model.filterBridgeType

                currentIndex =
                    case model.selectedThreadId of
                        Nothing ->
                            0

                        Just threadId ->
                            List.indexedMap Tuple.pair filteredThreads
                                |> List.filter (\( _, t ) -> t.id == threadId)
                                |> List.head
                                |> Maybe.map Tuple.first
                                |> Maybe.withDefault 0

                prevIndex =
                    max (currentIndex - 1) 0

                prevThread =
                    List.drop prevIndex filteredThreads
                        |> List.head
            in
            { model | selectedThreadId = Maybe.map .id prevThread }

        _ ->
            model


validateThreadName : String -> Result String String
validateThreadName name =
    if String.isEmpty name then
        Err "Thread name is required"

    else if String.length name < 3 then
        Err "Thread name must be at least 3 characters"

    else if String.length name > 100 then
        Err "Thread name must be less than 100 characters"

    else
        Ok name


truncate : Int -> String -> String
truncate maxLength str =
    if String.length str <= maxLength then
        str

    else
        String.left (maxLength - 3) str ++ "..."


bridgePlatformIcon : BridgePlatform -> String
bridgePlatformIcon platform =
    case platform of
        Slack ->
            "📧"

        Telegram ->
            "✈️"

        WhatsApp ->
            "💬"


bridgePlatformName : BridgePlatform -> String
bridgePlatformName platform =
    case platform of
        Slack ->
            "Slack"

        Telegram ->
            "Telegram"

        WhatsApp ->
            "WhatsApp"


bridgePlatformClass : BridgePlatform -> String
bridgePlatformClass platform =
    case platform of
        Slack ->
            "bridge-slack"

        Telegram ->
            "bridge-telegram"

        WhatsApp ->
            "bridge-whatsapp"


bridgeStatusClass : BridgeStatus -> String
bridgeStatusClass status =
    case status of
        Connected ->
            "status-connected"

        Syncing ->
            "status-syncing"

        Disconnected ->
            "status-disconnected"

        Error ->
            "status-error"


bridgeStatusText : BridgeStatus -> String
bridgeStatusText status =
    case status of
        Connected ->
            "Connected"

        Syncing ->
            "Syncing..."

        Disconnected ->
            "Disconnected"

        Error ->
            "Error"
