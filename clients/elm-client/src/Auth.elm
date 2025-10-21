module Auth exposing
    ( AuthState(..)
    , User
    , Credentials
    , LoginForm
    , LoginError(..)
    , validateEmail
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
    , email : String
    , createdAt : String
    }


{-| Login credentials
-}
type alias Credentials =
    { email : String
    , password : String
    , csrfToken : String
    }


{-| Login form state with validation
-}
type alias LoginForm =
    { email : String
    , password : String
    , emailError : Maybe String
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
    { email = ""
    , password = ""
    , emailError = Nothing
    , passwordError = Nothing
    , isSubmitting = False
    }


{-| Validate email format
-}
validateEmail : String -> Result String String
validateEmail email =
    if String.isEmpty email then
        Err "Email is required"

    else if not (String.contains "@" email && String.contains "." email) then
        Err "Please enter a valid email address"

    else
        Ok email


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
