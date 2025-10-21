module Main exposing (main)

import Api exposing (ApiConfig, defaultConfig)
import Auth exposing (AuthState(..))
import Browser
import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Html.Events
import Page.Login as Login
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
    | ThreadListPage
    | ConversationPage ThreadId


type alias Model =
    { flags : Flags
    , apiConfig : ApiConfig
    , authState : AuthState
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
    | SessionRestored (Maybe Ports.SessionData)
    | Logout
    | ThreadsMsg Threads.Msg
    | MessagesMsg Messages.Msg
    | BridgesMsg Bridges.Msg
    | NavigateToThreadList
    | NavigateToConversation ThreadId
    | NavigateToLogin
    | BootstrapLoaded (Result Api.ApiError Api.BootstrapData)


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
                        ( newAuthState, newPage, cmd ) =
                            case loginMsg of
                                Login.LoginResponse (Ok response) ->
                                    ( Authenticated response.user
                                    , ThreadListPage
                                    , Cmd.batch
                                        [ Ports.storeSession
                                            { accessToken = response.accessToken
                                            , refreshToken = response.refreshToken
                                            , userId = response.user.id
                                            , email = response.user.email
                                            }
                                        , Api.bootstrap model.apiConfig response.accessToken BootstrapLoaded
                                        ]
                                    )

                                Login.LoginResponse (Err _) ->
                                    ( AuthError Auth.InvalidCredentials
                                    , LoginPage updatedLogin
                                    , Cmd.none
                                    )

                                Login.FormSubmitted ->
                                    ( Authenticating
                                    , LoginPage updatedLogin
                                    , Cmd.map LoginMsg loginCmd
                                    )

                                _ ->
                                    ( model.authState
                                    , LoginPage updatedLogin
                                    , Cmd.map LoginMsg loginCmd
                                    )
                    in
                    ( { model
                        | currentPage = newPage
                        , authState = newAuthState
                      }
                    , cmd
                    )

                _ ->
                    ( model, Cmd.none )

        SessionRestored (Just sessionData) ->
            -- Session restored from storage
            let
                user =
                    { id = sessionData.userId
                    , email = sessionData.email
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
                , currentPage = ThreadListPage
              }
            , cmd
            )

        SessionRestored Nothing ->
            -- No stored session, stay on login page
            ( model, Cmd.none )

        BootstrapLoaded (Ok bootstrapData) ->
            -- Initialize application state with bootstrap data
            let
                ( threadsModel, threadsCmd ) =
                    Threads.update model.apiConfig "" (Threads.ThreadsLoaded (Ok bootstrapData.threads)) model.threads

                ( bridgesModel, bridgesCmd ) =
                    Bridges.update (Bridges.LoadBridges bootstrapData.bridges) model.bridges
            in
            ( { model
                | threads = threadsModel
                , bridges = bridgesModel
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
                , currentPage = LoginPage (Login.init model.apiConfig model.flags.csrfToken False)
                , threads = Threads.init
                , messages = Messages.init
                , bridges = Bridges.init
              }
            , Ports.clearSession ()
            )

        ThreadsMsg threadsMsg ->
            let
                token =
                    getAuthToken model.authState

                ( newThreads, cmd ) =
                    Threads.update model.apiConfig token threadsMsg model.threads
            in
            ( { model | threads = newThreads }
            , Cmd.map ThreadsMsg cmd
            )

        MessagesMsg messagesMsg ->
            let
                token =
                    getAuthToken model.authState

                ( newMessages, cmd ) =
                    Messages.update model.apiConfig token messagesMsg model.messages
            in
            ( { model | messages = newMessages }
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
            ( { model | currentPage = ThreadListPage }
            , Cmd.none
            )

        NavigateToConversation threadId ->
            ( { model | currentPage = ConversationPage threadId }
            , Cmd.map MessagesMsg (Cmd.batch [ Cmd.none ])
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
        , Sub.map ThreadsMsg (Threads.subscriptions model.threads)
        , Sub.map MessagesMsg (Messages.subscriptions model.messages)
        , Sub.map BridgesMsg (Bridges.subscriptions model.bridges)
        ]


-- VIEW


view : Model -> Html Msg
view model =
    case model.authState of
        Anonymous ->
            case model.currentPage of
                LoginPage loginModel ->
                    Html.map LoginMsg (Login.view loginModel)

                _ ->
                    div [ class "error" ] [ text "Error: Not authenticated" ]

        Authenticating ->
            div [ class "loading-container" ]
                [ text "Authenticating..." ]

        Authenticated user ->
            viewAuthenticatedPage model user

        AuthError error ->
            div [ class "error-container" ]
                [ text ("Authentication error: " ++ authErrorToString error) ]


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

                ThreadListPage ->
                    viewThreadListPage model user

                ConversationPage threadId ->
                    viewConversationPage model threadId
            ]
        ]


viewThreadListPage : Model -> Auth.User -> Html Msg
viewThreadListPage model user =
    div [ class "thread-list-container" ]
        [ div [ class "welcome-message" ]
            [ text ("Welcome, " ++ user.email ++ "!") ]
        , div [ class "placeholder" ]
            [ text "TODO: Thread list view (Task 6)" ]
        , div [ class "thread-list-status" ]
            [ case model.threads of
                Threads.Loading ->
                    text "Loading threads..."

                Threads.Ready threads ->
                    text (String.fromInt (List.length threads) ++ " threads loaded")

                Threads.Error err ->
                    text ("Error: " ++ err)

                Threads.NotLoaded ->
                    text "Threads not loaded"
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


getAuthToken : AuthState -> String
getAuthToken authState =
    case authState of
        Authenticated _ ->
            -- TODO: Store and retrieve actual token
            ""

        _ ->
            ""
