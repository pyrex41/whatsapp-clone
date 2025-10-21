module Page.Login exposing (Model, Msg(..), init, update, view)

{-| Login page for GlobalBridge Messenger.

Provides email/password authentication with form validation.

-}

import Api
import Auth exposing (AuthState(..), Credentials, LoginError(..), LoginForm)
import Html exposing (Html, button, div, form, h1, input, label, p, text)
import Html.Attributes exposing (class, disabled, placeholder, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Http


-- MODEL


type alias Model =
    { form : LoginForm
    , csrfToken : String
    , devMode : Bool
    }


init : String -> Bool -> Model
init csrfToken devMode =
    { form =
        if devMode then
            -- Developer mode preset credentials
            { email = "dev@globalbridge.io"
            , password = "dev123456"
            , emailError = Nothing
            , passwordError = Nothing
            , isSubmitting = False
            }

        else
            Auth.emptyLoginForm
    , csrfToken = csrfToken
    , devMode = devMode
    }


-- UPDATE


type Msg
    = EmailChanged String
    | PasswordChanged String
    | FormSubmitted
    | LoginResponse (Result Http.Error Api.LoginResponse)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        EmailChanged email ->
            let
                form =
                    model.form

                updatedForm =
                    { form | email = email, emailError = Nothing }
            in
            ( { model | form = updatedForm }, Cmd.none )

        PasswordChanged password ->
            let
                form =
                    model.form

                updatedForm =
                    { form | password = password, passwordError = Nothing }
            in
            ( { model | form = updatedForm }, Cmd.none )

        FormSubmitted ->
            case validateForm model.form of
                Ok credentials ->
                    let
                        form =
                            model.form

                        updatedForm =
                            { form | isSubmitting = True }

                        creds =
                            { credentials | csrfToken = model.csrfToken }
                    in
                    ( { model | form = updatedForm }
                    , Api.login creds LoginResponse
                    )

                Err form ->
                    ( { model | form = form }, Cmd.none )

        LoginResponse (Ok response) ->
            -- Success handled by Main module
            let
                form =
                    model.form

                updatedForm =
                    { form | isSubmitting = False }
            in
            ( { model | form = updatedForm }, Cmd.none )

        LoginResponse (Err error) ->
            let
                form =
                    model.form

                errorMessage =
                    httpErrorToString error

                updatedForm =
                    { form
                        | isSubmitting = False
                        , passwordError = Just errorMessage
                    }
            in
            ( { model | form = updatedForm }, Cmd.none )


validateForm : LoginForm -> Result LoginForm Credentials
validateForm form =
    let
        emailResult =
            Auth.validateEmail form.email

        passwordResult =
            Auth.validatePassword form.password
    in
    case ( emailResult, passwordResult ) of
        ( Ok email, Ok password ) ->
            Ok { email = email, password = password, csrfToken = "" }

        ( emailErr, passwordErr ) ->
            Err
                { form
                    | emailError = Result.toMaybe (Result.mapError identity emailErr)
                    , passwordError = Result.toMaybe (Result.mapError identity passwordErr)
                }


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl _ ->
            "Invalid URL"

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "Network error - please check your connection"

        Http.BadStatus 401 ->
            "Invalid email or password"

        Http.BadStatus 403 ->
            "Access forbidden"

        Http.BadStatus _ ->
            "Server error - please try again later"

        Http.BadBody _ ->
            "Invalid response from server"


-- VIEW


view : Model -> Html Msg
view model =
    div [ class "login-container" ]
        [ div [ class "login-card" ]
            [ h1 [ class "login-title" ] [ text "GlobalBridge Messenger" ]
            , p [ class "login-subtitle" ] [ text "Sign in to continue" ]
            , loginForm model.form
            , if model.devMode then
                p [ class "dev-mode-notice" ] [ text "🔧 Developer mode enabled" ]

              else
                text ""
            ]
        ]


loginForm : LoginForm -> Html Msg
loginForm form =
    Html.form [ class "login-form", onSubmit FormSubmitted ]
        [ div [ class "form-group" ]
            [ label [ class "form-label" ] [ text "Email" ]
            , input
                [ type_ "email"
                , class "form-input"
                , placeholder "you@example.com"
                , value form.email
                , onInput EmailChanged
                , disabled form.isSubmitting
                ]
                []
            , viewError form.emailError
            ]
        , div [ class "form-group" ]
            [ label [ class "form-label" ] [ text "Password" ]
            , input
                [ type_ "password"
                , class "form-input"
                , placeholder "••••••••"
                , value form.password
                , onInput PasswordChanged
                , disabled form.isSubmitting
                ]
                []
            , viewError form.passwordError
            ]
        , button
            [ type_ "submit"
            , class "btn btn-primary"
            , disabled (form.isSubmitting || not (isFormValid form))
            ]
            [ text
                (if form.isSubmitting then
                    "Signing in..."

                 else
                    "Sign In"
                )
            ]
        ]


viewError : Maybe String -> Html msg
viewError maybeError =
    case maybeError of
        Just error ->
            p [ class "form-error" ] [ text error ]

        Nothing ->
            text ""


isFormValid : LoginForm -> Bool
isFormValid form =
    not (String.isEmpty form.email) && not (String.isEmpty form.password)
