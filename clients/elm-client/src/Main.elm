module Main exposing (main)

import Api exposing (ApiConfig, defaultConfig)
import Auth exposing (AuthState(..))
import Browser
import Html exposing (Html, button, div, h1, p, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Json.Encode
import Page.Conversation as Conversation
import Page.Login as Login
import Page.ThreadList as ThreadList
import Ports
import State.Bridges as Bridges
import State.Messages as Messages
import State.Threads as Threads
import Types exposing (ThreadId)



-- MAIN


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- MODEL


type alias Flags =
    { csrfToken : String
    , apiUrl : String
    }


{-| Page represents the current view/route in the application.
Each page maintains its own state and lifecycle.
-}
type Page
    = LoginPage Login.Model
    | ThreadListPage ThreadList.Model
    | ConversationPage Conversation.Model


type alias Model =
    { flags : Flags
    , apiConfig : ApiConfig
    , authState : AuthState
    , accessToken : String
    , refreshToken : String
    , currentPage : Page
    , threads : Threads.Model
    , messages : Messages.Model
    , bridges : Bridges.Model
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        -- Create API configuration from flags
        apiConfig =
            defaultConfig flags.apiUrl

        -- Check if running in dev mode (set via environment)
        devMode =
            flags.apiUrl == "http://localhost:4000"

        loginModel =
            Login.init apiConfig flags.csrfToken devMode
    in
    ( { flags = flags
      , apiConfig = apiConfig
      , authState = Anonymous
      , accessToken = ""
      , refreshToken = ""
      , currentPage = LoginPage loginModel
      , threads = Threads.init
      , messages = Messages.init
      , bridges = Bridges.init
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = LoginMsg Login.Msg
    | ThreadListMsg ThreadList.Msg
    | ConversationMsg Conversation.Msg
    | SessionRestored (Maybe Ports.SessionData)
    | Logout
    | ThreadsMsg Threads.Msg
    | MessagesMsg Messages.Msg
    | BridgesMsg Bridges.Msg
    | NavigateToThreadList
    | NavigateToConversation ThreadId
    | NavigateToLogin
    | BootstrapLoaded (Result Api.ApiError Api.BootstrapData)
    | Auth0LoginClicked
    | Auth0LoginComplete Ports.SessionData
    | Auth0LoginError String
    | SocketConnected Bool
    | UserChannelJoined { topic : String, data : Json.Encode.Value }
    | BootstrapReceived { topic : String, event : String, payload : Json.Encode.Value }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LoginMsg loginMsg ->
            case model.currentPage of
                LoginPage loginModel ->
                    let
                        ( updatedLogin, loginCmd ) =
                            Login.update loginMsg loginModel

                        -- Handle successful login
                        result =
                            case loginMsg of
                                Login.LoginResponse (Ok response) ->
                                    { authState = Authenticated response.user
                                    , accessToken = response.accessToken
                                    , refreshToken = response.refreshToken
                                    , page = ThreadListPage (ThreadList.init model.threads)
                                    , cmd =
                                        Cmd.batch
                                            [ -- Don't use old login anymore - use Auth0
                                              -- Ports.storeSession is for Auth0 flow only
                                              Api.bootstrap model.apiConfig response.accessToken BootstrapLoaded
                                            ]
                                    }

                                Login.LoginResponse (Err _) ->
                                    { authState = AuthError Auth.InvalidCredentials
                                    , accessToken = model.accessToken
                                    , refreshToken = model.refreshToken
                                    , page = LoginPage updatedLogin
                                    , cmd = Cmd.none
                                    }

                                Login.FormSubmitted ->
                                    { authState = Authenticating
                                    , accessToken = model.accessToken
                                    , refreshToken = model.refreshToken
                                    , page = LoginPage updatedLogin
                                    , cmd = Cmd.map LoginMsg loginCmd
                                    }

                                _ ->
                                    { authState = model.authState
                                    , accessToken = model.accessToken
                                    , refreshToken = model.refreshToken
                                    , page = LoginPage updatedLogin
                                    , cmd = Cmd.map LoginMsg loginCmd
                                    }
                    in
                    ( { model
                        | currentPage = result.page
                        , authState = result.authState
                        , accessToken = result.accessToken
                        , refreshToken = result.refreshToken
                      }
                    , result.cmd
                    )

                _ ->
                    ( model, Cmd.none )

        SessionRestored (Just sessionData) ->
            -- Session restored from storage
            let
                user =
                    { id = sessionData.userId
                    , username = sessionData.username
                    , phoneNumber = ""
                    , createdAt = ""
                    }

                -- Load bootstrap data with restored token
                cmd =
                    case sessionData.accessToken of
                        "" ->
                            Cmd.none

                        token ->
                            Api.bootstrap model.apiConfig token BootstrapLoaded
            in
            ( { model
                | authState = Authenticated user
                , accessToken = sessionData.accessToken
                , refreshToken = sessionData.refreshToken
                , currentPage = ThreadListPage (ThreadList.init model.threads)
              }
            , cmd
            )

        SessionRestored Nothing ->
            -- No stored session, stay on login page
            ( model, Cmd.none )

        Auth0LoginClicked ->
            -- Trigger Auth0 login via port
            ( { model | authState = Authenticating }
            , Ports.auth0Login ()
            )

        Auth0LoginComplete sessionData ->
            -- Auth0 login successful
            let
                user =
                    { id = sessionData.userId
                    , username = sessionData.username
                    , phoneNumber = ""
                    , createdAt = ""
                    }

                socketEndpoint =
                    if model.apiConfig.baseUrl == "" then
                        "ws://localhost:4000/socket"

                    else
                        String.replace "http" "ws" model.apiConfig.baseUrl ++ "/socket"
            in
            ( { model
                | authState = Authenticated user
                , accessToken = sessionData.accessToken
                , refreshToken = sessionData.refreshToken
                , currentPage = ThreadListPage (ThreadList.init model.threads)
              }
            , Cmd.batch
                [ -- Initialize Phoenix socket with Auth0 token
                  Ports.initSocket { endpoint = socketEndpoint, token = sessionData.accessToken }
                , -- Store session
                  Ports.storeSession sessionData
                ]
            )

        Auth0LoginError errorMsg ->
            ( { model | authState = AuthError (Auth.NetworkError errorMsg) }
            , Cmd.none
            )

        SocketConnected isConnected ->
            if isConnected && model.authState /= Anonymous then
                -- Socket connected, join user channel for bootstrap
                case model.authState of
                    Authenticated user ->
                        ( model
                        , Ports.joinChannel
                            { topic = "user:" ++ user.id
                            , params = Json.Encode.object []
                            }
                        )

                    _ ->
                        ( model, Cmd.none )

            else
                ( model, Cmd.none )

        UserChannelJoined { topic } ->
            -- User channel joined, request bootstrap
            ( model
            , Ports.sendChannelMessage
                { topic = topic
                , event = "bootstrap"
                , payload = Json.Encode.object []
                }
            )

        BootstrapReceived { payload } ->
            -- Bootstrap data received from user channel
            -- Decode and update threads
            ( model, Cmd.none )

        BootstrapLoaded (Ok bootstrapData) ->
            -- Initialize application state with bootstrap data
            let
                ( threadsModel, threadsCmd ) =
                    Threads.update model.apiConfig model.accessToken (Threads.ThreadsLoaded (Ok bootstrapData.threads)) model.threads

                ( bridgesModel, bridgesCmd ) =
                    Bridges.update (Bridges.LoadBridges bootstrapData.bridges) model.bridges

                -- Update the current page with new threads state if on thread list
                updatedPage =
                    case model.currentPage of
                        ThreadListPage threadListModel ->
                            ThreadListPage { threadListModel | threadsState = threadsModel }

                        other ->
                            other
            in
            ( { model
                | threads = threadsModel
                , bridges = bridgesModel
                , currentPage = updatedPage
              }
            , Cmd.batch
                [ Cmd.map ThreadsMsg threadsCmd
                , Cmd.map BridgesMsg bridgesCmd
                ]
            )

        BootstrapLoaded (Err _) ->
            -- Bootstrap failed, logout
            ( { model
                | authState = Anonymous
                , currentPage = LoginPage (Login.init model.apiConfig model.flags.csrfToken False)
              }
            , Ports.clearSession ()
            )

        Logout ->
            ( { model
                | authState = Anonymous
                , accessToken = ""
                , refreshToken = ""
                , currentPage = LoginPage (Login.init model.apiConfig model.flags.csrfToken False)
                , threads = Threads.init
                , messages = Messages.init
                , bridges = Bridges.init
              }
            , Ports.clearSession ()
            )

        ThreadListMsg threadListMsg ->
            case model.currentPage of
                ThreadListPage threadListModel ->
                    let
                        ( updatedThreadList, cmd ) =
                            ThreadList.update threadListMsg threadListModel
                    in
                    ( { model | currentPage = ThreadListPage updatedThreadList }
                    , Cmd.map ThreadListMsg cmd
                    )

                _ ->
                    ( model, Cmd.none )

        ConversationMsg conversationMsg ->
            case model.currentPage of
                ConversationPage conversationModel ->
                    let
                        ( updatedConversation, cmd ) =
                            Conversation.update conversationMsg conversationModel

                        -- Handle SendMessage by triggering Messages state update
                        ( newMessages, messagesCmd ) =
                            case conversationMsg of
                                Conversation.SendMessage ->
                                    if String.isEmpty (String.trim conversationModel.composerText) then
                                        ( model.messages, Cmd.none )

                                    else
                                        Messages.update model.apiConfig
                                            (getAuthToken model)
                                            (Messages.SendMessage conversationModel.threadId conversationModel.composerText)
                                            model.messages

                                _ ->
                                    ( model.messages, Cmd.none )

                        -- Update conversation page with new messages state
                        updatedPage =
                            ConversationPage { updatedConversation | messagesState = newMessages }
                    in
                    ( { model | currentPage = updatedPage, messages = newMessages }
                    , Cmd.batch
                        [ Cmd.map ConversationMsg cmd
                        , Cmd.map MessagesMsg messagesCmd
                        ]
                    )

                _ ->
                    ( model, Cmd.none )

        ThreadsMsg threadsMsg ->
            let
                token =
                    getAuthToken model

                ( newThreads, cmd ) =
                    Threads.update model.apiConfig token threadsMsg model.threads

                -- Update ThreadList view if it's the current page
                updatedPage =
                    case model.currentPage of
                        ThreadListPage threadListModel ->
                            ThreadListPage { threadListModel | threadsState = newThreads }

                        other ->
                            other
            in
            ( { model | threads = newThreads, currentPage = updatedPage }
            , Cmd.map ThreadsMsg cmd
            )

        MessagesMsg messagesMsg ->
            let
                token =
                    getAuthToken model

                ( newMessages, cmd ) =
                    Messages.update model.apiConfig token messagesMsg model.messages

                -- Update ConversationPage if it's the current page
                updatedPage =
                    case model.currentPage of
                        ConversationPage conversationModel ->
                            ConversationPage { conversationModel | messagesState = newMessages }

                        other ->
                            other
            in
            ( { model | messages = newMessages, currentPage = updatedPage }
            , Cmd.map MessagesMsg cmd
            )

        BridgesMsg bridgesMsg ->
            let
                ( newBridges, cmd ) =
                    Bridges.update bridgesMsg model.bridges
            in
            ( { model | bridges = newBridges }
            , Cmd.map BridgesMsg cmd
            )

        NavigateToThreadList ->
            ( { model | currentPage = ThreadListPage (ThreadList.init model.threads) }
            , Cmd.none
            )

        NavigateToConversation threadId ->
            let
                -- Find thread name from threads state
                threadName =
                    Threads.getThreads model.threads
                        |> List.filter (\t -> t.id == threadId)
                        |> List.head
                        |> Maybe.map .name
                        |> Maybe.withDefault "Conversation"

                -- Create conversation model
                conversationModel =
                    Conversation.init threadId threadName model.messages
            in
            ( { model | currentPage = ConversationPage conversationModel }
            , Cmd.map MessagesMsg (Messages.update model.apiConfig (getAuthToken model) (Messages.LoadMessages threadId) model.messages |> Tuple.second)
            )

        NavigateToLogin ->
            ( { model
                | currentPage = LoginPage (Login.init model.apiConfig model.flags.csrfToken False)
                , authState = Anonymous
              }
            , Ports.clearSession ()
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.onSessionRestored SessionRestored
        , Ports.onAuth0LoginComplete Auth0LoginComplete
        , Ports.onAuth0LoginError Auth0LoginError
        , Ports.onSocketConnected SocketConnected
        , Ports.onChannelJoined UserChannelJoined
        , Ports.onChannelMessage BootstrapReceived
        , Sub.map ThreadsMsg (Threads.subscriptions model.threads)
        , Sub.map MessagesMsg (Messages.subscriptions model.messages)
        , Sub.map BridgesMsg (Bridges.subscriptions model.bridges)
        ]



-- VIEW


view : Model -> Html Msg
view model =
    case model.authState of
        Anonymous ->
            viewAuth0Login

        Authenticating ->
            div [ class "loading-container" ]
                [ text "Authenticating with Auth0..." ]

        Authenticated user ->
            viewAuthenticatedPage model user

        AuthError error ->
            div [ class "error-container" ]
                [ div [] [ text ("Authentication error: " ++ authErrorToString error) ]
                , button [ onClick Auth0LoginClicked, class "btn btn-primary mt-4" ]
                    [ text "Try Again" ]
                ]


viewAuth0Login : Html Msg
viewAuth0Login =
    div [ class "auth0-login-container min-h-screen flex items-center justify-center bg-gray-100" ]
        [ div [ class "auth0-card bg-white p-8 rounded-lg shadow-lg max-w-md w-full" ]
            [ div [ class "text-center mb-8" ]
                [ h1 [ class "text-3xl font-bold text-gray-900 mb-2" ]
                    [ text "GlobalBridge" ]
                , p [ class "text-gray-600" ]
                    [ text "Secure messaging platform" ]
                ]
            , button
                [ onClick Auth0LoginClicked
                , class "w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-3 px-4 rounded-lg transition duration-200"
                ]
                [ text "Login with Auth0" ]
            , div [ class "mt-4 text-center text-sm text-gray-500" ]
                [ text "Secure authentication powered by Auth0" ]
            ]
        ]


viewAuthenticatedPage : Model -> Auth.User -> Html Msg
viewAuthenticatedPage model user =
    div [ class "app-container" ]
        [ Html.nav [ class "app-nav" ]
            [ Html.h2 [] [ text "GlobalBridge" ]
            , Html.button [ class "btn btn-secondary", Html.Events.onClick Logout ] [ text "Logout" ]
            ]
        , Html.main_ [ class "app-main" ]
            [ case model.currentPage of
                LoginPage _ ->
                    div [] [ text "Redirecting..." ]

                ThreadListPage threadListModel ->
                    Html.map ThreadListMsg (ThreadList.view threadListModel)

                ConversationPage conversationModel ->
                    Html.map ConversationMsg (Conversation.view conversationModel)
            ]
        ]


viewConversationPage : Model -> ThreadId -> Html Msg
viewConversationPage model threadId =
    div [ class "conversation-container" ]
        [ div [ class "placeholder" ]
            [ text ("TODO: Conversation view for thread " ++ threadId ++ " (Task 7)") ]
        ]



-- HELPERS


authErrorToString : Auth.LoginError -> String
authErrorToString error =
    case error of
        Auth.InvalidCredentials ->
            "Invalid credentials"

        Auth.NetworkError msg ->
            "Network error: " ++ msg

        Auth.ValidationError msg ->
            "Validation error: " ++ msg

        Auth.TokenExpired ->
            "Session expired"

        Auth.UnknownError msg ->
            "Unknown error: " ++ msg


getAuthToken : Model -> String
getAuthToken model =
    case model.authState of
        Authenticated _ ->
            model.accessToken

        _ ->
            ""
