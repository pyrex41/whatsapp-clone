module Auth exposing
    ( AuthState(..)
    , User
    , Credentials
    , LoginForm
    , LoginError(..)
    , validateIdentifier
    , validatePassword
    , emptyLoginForm
    )

{-| Authentication module for GlobalBridge Elm client.

Manages authentication state, user data, and login form validation.

-}


-- TYPES


{-| Authentication state machine
-}
type AuthState
    = Anonymous
    | Authenticating
    | Authenticated User
    | AuthError LoginError


{-| User information after successful authentication
-}
type alias User =
    { id : String
    , username : String
    , phoneNumber : String
    , createdAt : String
    }


{-| Login credentials
-}
type alias Credentials =
    { identifier : String
    , password : String
    , csrfToken : String
    }


{-| Login form state with validation
-}
type alias LoginForm =
    { identifier : String
    , password : String
    , identifierError : Maybe String
    , passwordError : Maybe String
    , isSubmitting : Bool
    }


{-| Login error types
-}
type LoginError
    = InvalidCredentials
    | NetworkError String
    | ValidationError String
    | TokenExpired
    | UnknownError String


-- FORM HELPERS


{-| Create an empty login form
-}
emptyLoginForm : LoginForm
emptyLoginForm =
    { identifier = ""
    , password = ""
    , identifierError = Nothing
    , passwordError = Nothing
    , isSubmitting = False
    }


{-| Validate identifier (username or phone number)
-}
validateIdentifier : String -> Result String String
validateIdentifier identifier =
    if String.isEmpty identifier then
        Err "Username or phone number is required"

    else if String.length identifier < 3 then
        Err "Username or phone number must be at least 3 characters"

    else
        Ok identifier


{-| Validate password requirements
-}
validatePassword : String -> Result String String
validatePassword password =
    if String.isEmpty password then
        Err "Password is required"

    else if String.length password < 8 then
        Err "Password must be at least 8 characters"

    else
        Ok password
