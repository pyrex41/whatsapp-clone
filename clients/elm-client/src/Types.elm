module Types exposing
    ( Thread
    , ThreadId
    , Bridge
    , BridgeId
    , BridgeStatus(..)
    , BridgePlatform(..)
    , BridgeConfig
    , Message
    , MessageId
    , DeliveryStatus(..)
    , Attachment
    , AttachmentType(..)
    )

{-| Core domain types for GlobalBridge Messenger.

Shared across modules for threads, messages, and bridges.

-}


-- IDENTIFIERS


type alias ThreadId =
    String


type alias MessageId =
    String


type alias BridgeId =
    String


-- THREADS


type alias Thread =
    { id : ThreadId
    , name : String
    , lastMessage : Maybe Message
    , unreadCount : Int
    , bridge : Maybe Bridge
    , createdAt : String
    , updatedAt : String
    }


-- MESSAGES


type alias Message =
    { id : MessageId
    , threadId : ThreadId
    , content : String
    , senderId : String
    , senderName : String
    , senderAvatar : Maybe String
    , createdAt : String
    , encrypted : Bool
    , bridgeOrigin : Maybe String
    , deliveryStatus : DeliveryStatus
    , attachments : List Attachment
    }


type DeliveryStatus
    = Pending
    | Sent
    | Delivered
    | Read
    | Failed


type AttachmentType
    = Image
    | Video
    | Audio
    | Document
    | Other


type alias Attachment =
    { id : String
    , attachmentType : AttachmentType
    , fileName : String
    , fileSize : Int
    , url : String
    , thumbnailUrl : Maybe String
    }


-- BRIDGES


type alias Bridge =
    { id : BridgeId
    , threadId : ThreadId
    , platform : BridgePlatform
    , status : BridgeStatus
    , config : BridgeConfig
    , lastSyncAt : Maybe String
    , errorMessage : Maybe String
    }


type BridgePlatform
    = Slack
    | Telegram
    | WhatsApp


type BridgeStatus
    = Connected
    | Syncing
    | Disconnected
    | Error


type alias BridgeConfig =
    { channelId : Maybe String
    , channelName : Maybe String
    }
