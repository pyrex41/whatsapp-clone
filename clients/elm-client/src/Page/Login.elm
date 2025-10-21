module Page.Login exposing (Model, Msg(..), init, update, view)

{-| Login page for GlobalBridge Messenger.

Provides username/phone authentication with form validation.

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
    , apiConfig : Api.ApiConfig
    }


init : Api.ApiConfig -> String -> Bool -> Model
init apiConfig csrfToken devMode =
    { form =
        if devMode then
            -- Developer mode preset credentials
            { identifier = "devuser"
            , password = "dev123456"
            , identifierError = Nothing
            , passwordError = Nothing
            , isSubmitting = False
            }

        else
            Auth.emptyLoginForm
    , csrfToken = csrfToken
    , devMode = devMode
    , apiConfig = apiConfig
    }


-- UPDATE


type Msg
    = IdentifierChanged String
    | PasswordChanged String
    | FormSubmitted
    | LoginResponse (Result Api.ApiError Api.LoginResponse)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        IdentifierChanged identifier ->
            let
                form =
                    model.form

                updatedForm =
                    { form | identifier = identifier, identifierError = Nothing }
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
                    , Api.login model.apiConfig creds LoginResponse
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
        identifierResult =
            Auth.validateIdentifier form.identifier

        passwordResult =
            Auth.validatePassword form.password
    in
    case ( identifierResult, passwordResult ) of
        ( Ok identifier, Ok password ) ->
            Ok { identifier = identifier, password = password, csrfToken = "" }

        ( identifierErr, passwordErr ) ->
            Err
                { form
                    | identifierError = Result.toMaybe (Result.mapError identity identifierErr)
                    , passwordError = Result.toMaybe (Result.mapError identity passwordErr)
                }


httpErrorToString : Api.ApiError -> String
httpErrorToString error =
    case error of
        Api.NetworkError ->
            "Network error - please check your connection"

        Api.Timeout ->
            "Request timed out"

        Api.BadStatus 401 _ ->
            "Invalid username/phone or password"

        Api.BadStatus 403 _ ->
            "Access forbidden"

        Api.BadStatus _ _ ->
            "Server error - please try again later"

        Api.BadBody msg ->
            "Invalid response: " ++ msg

        Api.Unauthorized ->
            "Invalid username/phone or password"

        Api.NotFound ->
            "Service not found"

        Api.ServerError msg ->
            "Server error: " ++ msg


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
            [ label [ class "form-label" ] [ text "Username or Phone" ]
            , input
                [ type_ "text"
                , class "form-input"
                , placeholder "username or +1234567890"
                , value form.identifier
                , onInput IdentifierChanged
                , disabled form.isSubmitting
                ]
                []
            , viewError form.identifierError
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
    not (String.isEmpty form.identifier) && not (String.isEmpty form.password)
