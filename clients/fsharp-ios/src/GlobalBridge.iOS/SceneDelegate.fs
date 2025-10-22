namespace GlobalBridge.iOS

open UIKit
open Foundation
open GlobalBridge.UI
open GlobalBridge.Core.Auth
open GlobalBridge.Core.Domain
open GlobalBridge.iOS.Auth
open GlobalBridge.Networking
open GlobalBridge.Networking.AuthApi
open GlobalBridge.Networking.DemoData
open GlobalBridge.Networking.AuthHttp
open System
open System.Net.Http
open System.Threading.Tasks
open System.IO
open Microsoft.FSharp.Control
open System.Collections.Generic

[<Register(nameof SceneDelegate)>]
type SceneDelegate() =
    inherit UIResponder()
    let subscriptions = List<IDisposable>()
    [<Export("window")>]
    member val Window : UIWindow = null with get, set

    [<Export("scene:willConnectToSession:options:")>]
    member this.WillConnect(scene: UIScene, session: UISceneSession, connectionOptions: UISceneConnectionOptions) =
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // Since we are not using a storyboard, the `window` property needs to be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see UIApplicationDelegate `GetConfiguration` instead).
        match scene with
        | :? UIWindowScene as windowScene ->
            if isNull this.Window then
                this.Window <- new UIWindow(windowScene)

            let authEvents = Event<AuthMsg>()

            let getEnv key =
                match Environment.GetEnvironmentVariable(key) with
                | null
                | "" -> None
                | value -> Some value

            let required key fallback =
                getEnv key |> Option.defaultValue fallback

            let domain = required "AUTH0_DOMAIN" "https://example.auth0.com"
            let clientId = required "AUTH0_CLIENT_ID" "development-client-id"
            let audience = getEnv "AUTH0_AUDIENCE"
            let callbackScheme = (required "AUTH0_CALLBACK_SCHEME" "globalbridge") |> fun scheme -> scheme.Replace(":" , "")
            let backendBaseUri =
                required "BACKEND_BASE_URI" "https://api.globalbridge.dev"
                |> fun value -> Uri(value)

            let config =
                { Auth0Config.Domain = Uri(domain)
                  ClientId = clientId
                  Audience = audience
                  CallbackScheme = callbackScheme }

            let httpFactory () =
                let handler = new HttpClientHandler()
                new HttpClient(handler, disposeHandler = true)

            // Factory that injects Authorization header using the current access token
            let authHttpFactory : unit -> HttpClient =
                createAuthenticatedClientFromValueTask tokenProvider

            let coordinator =
                new AuthCoordinator(
                    { Config = config
                      HttpClientFactory = httpFactory
                      BackendBaseUri = backendBaseUri
                      Dispatch = authEvents.Trigger })

            let tokenProvider () =
                let task = task {
                    let! refreshed = coordinator.RefreshIfNeededAsync()
                    match refreshed with
                    | Some tokens -> return tokens.AccessToken
                    | None ->
                        match coordinator.CurrentTokens with
                        | Some tokens -> return tokens.AccessToken
                        | None -> return String.Empty
                }
                ValueTask<string>(task)

            let databasePath =
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "globalbridge.sqlite")

            let reconnectDelays =
                [ TimeSpan.FromSeconds 1.
                  TimeSpan.FromSeconds 3.
                  TimeSpan.FromSeconds 10. ]

            let channelEndpoint = required "PHOENIX_ENDPOINT" "wss://localhost/socket"

            let demoParticipant =
                { Participant.Id = "demo-user"
                  DisplayName = "Demo Operator"
                  AvatarUrl = Some "https://example.com/demo.png" }

            let messaging =
                new MessagingService(
                    { ChannelConfig =
                        { Endpoint = Uri(channelEndpoint)
                          TokenProvider = tokenProvider
                          HeartbeatInterval = TimeSpan.FromSeconds 30.
                          ReconnectDelays = reconnectDelays }
                      StoreConfig = { DatabasePath = databasePath }
                      LocalParticipant = demoParticipant })

            MessageStore.initialize { DatabasePath = databasePath }

            let loadThreads () = messaging.LoadThreadsAsync() |> Async.AwaitTask |> Async.Ignore

            let createConversation threadSummary =
                let convDeps : ConversationDependencies =
                    { LoadMessages = messaging.BootstrapFromLocal
                      SendMessage = (fun (threadId, content) -> messaging.SendMessageAsync(threadId, content) |> Async.AwaitTask)
                      MessagingEvents = messaging.Events
                      JoinThread = fun threadId -> messaging.JoinThreadAsync(threadId) |> Async.AwaitTask |> Async.StartImmediate
                      LeaveThread = fun threadId -> messaging.LeaveThreadAsync(threadId) |> Async.AwaitTask |> Async.StartImmediate }
                new ConversationViewController(threadSummary, convDeps) :> UIViewController

            let dependencies : AppShell.Dependencies =
                { StartLogin = (fun () ->
                      async {
                          match Option.ofObj this.Window with
                          | Some window -> do! coordinator.StartLoginAsync(window) |> Async.AwaitTask
                          | None -> return ()
                      })
                  Logout = coordinator.SignOut
                  LoadThreads = loadThreads
                  MessagingEvents = messaging.Events
                  AuthEvents = authEvents.Publish
                  CreateConversation = createConversation }

            let navigationController = AppShell.createRootViewController dependencies
            this.Window.RootViewController <- navigationController
            this.Window.MakeKeyAndVisible()

            if MessageStore.listThreads { DatabasePath = databasePath } |> List.isEmpty then
                DemoData.seed { DatabasePath = databasePath }

            let authSubscription =
                authEvents.Publish.Subscribe(fun msg ->
                    match msg with
                    | LoginSucceeded (_, profileOpt) ->
                        let participant =
                            match profileOpt with
                            | Some profile ->
                                { Participant.Id = profile.Subject
                                  DisplayName = profile.Name |> Option.defaultValue "You"
                                  AvatarUrl = None }
                            | None -> demoParticipant
                        messaging.SetLocalParticipant participant
                        this.InvokeOnMainThread(fun () ->
                            messaging.LoadThreadsAsync() |> Async.AwaitTask |> Async.Ignore |> Async.StartImmediate)
                    | Logout -> messaging.SetLocalParticipant demoParticipant
                    | LoginFailed reason ->
                        this.InvokeOnMainThread(fun () ->
                            if not (isNull this.Window) && not (isNull this.Window.RootViewController) then
                                let alert = UIAlertController.Create("Authentication Failed", reason, UIAlertControllerStyle.Alert)
                                alert.AddAction(UIAlertAction.Create("OK", UIAlertActionStyle.Default, null))
                                this.Window.RootViewController.PresentViewController(alert, true, null))
                    | _ -> ())
            subscriptions.Add authSubscription

            match coordinator.RestoreSession() with
            | Some (tokens, profile) ->
                authEvents.Trigger (LoginSucceeded (tokens, profile))
                coordinator.RefreshIfNeededAsync() |> Async.AwaitTask |> Async.Ignore |> Async.StartImmediate
            | None -> ()
        | _ -> ()

    override _.Dispose(disposing) =
        if disposing then
            for sub in subscriptions do
                sub.Dispose()
            subscriptions.Clear()
        base.Dispose(disposing)


    [<Export("sceneDidDisconnect:")>]
    member _.DidDisconnect(scene: UIScene) =
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not neccessarily discarded (see UIApplicationDelegate `DidDiscardSceneSessions` instead).
        ()

    [<Export("sceneDidBecomeActive:")>]
    member _.DidBecomeActive(scene: UIScene) =
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        ()

    [<Export("sceneWillResignActive:")>]
    member _.WillResignActive(scene: UIScene) =
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
        ()

    [<Export("sceneWillEnterForeground:")>]
    member _.WillEnterForeground(scene: UIScene) =
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        ()

    [<Export("sceneDidEnterBackground:")>]
    member _.DidEnterBackground(scene: UIScene) =
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        ()

    interface IUIWindowSceneDelegate
