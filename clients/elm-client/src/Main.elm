module Main exposing (main)

import Api
import Auth exposing (AuthState(..))
import Browser
import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Html.Events
import Http
import Page.Login as Login
import Ports


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


type alias Model =
    { flags : Flags
    , authState : AuthState
    , loginPage : Maybe Login.Model
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        -- Check if running in dev mode (set via environment)
        devMode =
            flags.apiUrl == "http://localhost:4000"

        loginModel =
            Login.init flags.csrfToken devMode
    in
    ( { flags = flags
      , authState = Anonymous
      , loginPage = Just loginModel
      }
    , Cmd.none
    )


-- UPDATE


type Msg
    = LoginMsg Login.Msg
    | GotLoginResponse (Result Http.Error Api.LoginResponse)
    | SessionRestored (Maybe Ports.SessionData)
    | Logout


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LoginMsg loginMsg ->
            case model.loginPage of
                Just loginModel ->
                    let
                        ( updatedLogin, loginCmd ) =
                            Login.update loginMsg loginModel

                        -- Map the login command and update state
                        ( newAuthState, cmd ) =
                            case loginMsg of
                                Login.LoginResponse (Ok response) ->
                                    ( Authenticated response.user
                                    , Ports.storeSession
                                        { accessToken = response.accessToken
                                        , refreshToken = response.refreshToken
                                        , userId = response.user.id
                                        , email = response.user.email
                                        }
                                    )

                                Login.LoginResponse (Err _) ->
                                    ( AuthError Auth.InvalidCredentials
                                    , Cmd.none
                                    )

                                Login.FormSubmitted ->
                                    ( Authenticating
                                    , Cmd.map LoginMsg loginCmd
                                    )

                                _ ->
                                    ( model.authState
                                    , Cmd.map LoginMsg loginCmd
                                    )
                    in
                    ( { model
                        | loginPage = Just updatedLogin
                        , authState = newAuthState
                      }
                    , cmd
                    )

                Nothing ->
                    ( model, Cmd.none )

        GotLoginResponse (Ok response) ->
            ( { model
                | authState = Authenticated response.user
                , loginPage = Nothing
              }
            , Cmd.none
            )

        GotLoginResponse (Err _) ->
            ( { model | authState = AuthError (Auth.NetworkError "Login failed") }
            , Cmd.none
            )

        SessionRestored (Just sessionData) ->
            -- Session restored from storage
            let
                user =
                    { id = sessionData.userId
                    , email = sessionData.email
                    , createdAt = ""
                    }
            in
            ( { model | authState = Authenticated user, loginPage = Nothing }
            , Cmd.none
            )

        SessionRestored Nothing ->
            -- No stored session, stay on login page
            ( model, Cmd.none )

        Logout ->
            ( { model | authState = Anonymous, loginPage = Just (Login.init model.flags.csrfToken False) }
            , Ports.clearSession ()
            )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Ports.onSessionRestored SessionRestored


-- VIEW


view : Model -> Html Msg
view model =
    case model.authState of
        Anonymous ->
            case model.loginPage of
                Just loginModel ->
                    Html.map LoginMsg (Login.view loginModel)

                Nothing ->
                    div [ class "error" ] [ text "Error: Login page not initialized" ]

        Authenticating ->
            div [ class "loading-container" ]
                [ text "Authenticating..." ]

        Authenticated user ->
            div [ class "app-container" ]
                [ Html.nav [ class "app-nav" ]
                    [ Html.h2 [] [ text "GlobalBridge" ]
                    , Html.button [ class "btn btn-secondary", Html.Events.onClick Logout ] [ text "Logout" ]
                    ]
                , Html.main_ [ class "app-main" ]
                    [ div [ class "welcome-message" ]
                        [ text ("Welcome, " ++ user.email ++ "!") ]
                    , div [ class "placeholder" ]
                        [ text "TODO: Thread list view (Task 6)" ]
                    ]
                ]

        AuthError error ->
            div [ class "error-container" ]
                [ text ("Authentication error: " ++ authErrorToString error) ]


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
