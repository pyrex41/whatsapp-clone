// JavaScript entry point for Elm application
import { Elm } from './Main.elm'
import * as PhoenixAdapter from './phoenixAdapter.js'
import * as Auth0Client from './auth0.js'

// Get CSRF token from meta tag (will be set by Phoenix)
const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || ''

// Get API URL from environment
// In development, empty string uses Vite proxy (localhost:3000 -> localhost:4000)
// In production, use full URL
const apiUrl = import.meta.env.VITE_API_URL || ''

// Session storage keys
const SESSION_KEY = 'globalbridge_session'
const TOKEN_EXPIRY_KEY = 'globalbridge_token_expiry'

// Initialize Elm application
const app = Elm.Main.init({
  node: document.getElementById('elm-app'),
  flags: {
    csrfToken,
    apiUrl
  }
})

// Make app globally accessible for Phoenix adapter
window.elmApp = app

// Session Management Ports

/**
 * Store session data in localStorage
 * Uses httpOnly cookies for tokens in production, localStorage for dev
 */
if (app.ports && app.ports.storeSession) {
  app.ports.storeSession.subscribe((sessionData) => {
    try {
      // Store session data (excluding tokens in production)
      const safeData = {
        userId: sessionData.userId,
        username: sessionData.username,
        // In development, store tokens for easier testing
        // In production, tokens are httpOnly cookies
        ...(import.meta.env.DEV && {
          accessToken: sessionData.accessToken,
          refreshToken: sessionData.refreshToken
        })
      }

      localStorage.setItem(SESSION_KEY, JSON.stringify(safeData))

      // Set token expiry (1 hour from now)
      const expiry = Date.now() + (60 * 60 * 1000)
      localStorage.setItem(TOKEN_EXPIRY_KEY, expiry.toString())

      console.log('[Session] Stored session for user:', sessionData.username)
    } catch (error) {
      console.error('[Session] Failed to store session:', error)
    }
  })
}

/**
 * Clear session data from storage
 */
if (app.ports && app.ports.clearSession) {
  app.ports.clearSession.subscribe(() => {
    try {
      localStorage.removeItem(SESSION_KEY)
      localStorage.removeItem(TOKEN_EXPIRY_KEY)
      console.log('[Session] Cleared session')
    } catch (error) {
      console.error('[Session] Failed to clear session:', error)
    }
  })
}

/**
 * Restore session on app startup (Auth0-based)
 */
async function restoreSession() {
  try {
    // Initialize Auth0 and check if authenticated
    await Auth0Client.initAuth0()
    
    const sessionData = await Auth0Client.getSessionData()
    
    if (sessionData) {
      console.log('[Session] Restored Auth0 session for user:', sessionData.username)
      
      if (app.ports && app.ports.onSessionRestored) {
        app.ports.onSessionRestored.send(sessionData)
      }
    } else {
      console.log('[Session] No Auth0 session found')
      
      if (app.ports && app.ports.onSessionRestored) {
        app.ports.onSessionRestored.send(null)
      }
    }
  } catch (error) {
    console.error('[Session] Failed to restore session:', error)
    if (app.ports && app.ports.onSessionRestored) {
      app.ports.onSessionRestored.send(null)
    }
  }
}

// Restore session on startup
restoreSession().then(async () => {
  // If no session was restored and auto-login is enabled, trigger Auth0 login
  const autoLogin = (import.meta.env.VITE_AUTH0_AUTO_LOGIN || 'false').toLowerCase() === 'true'
  const session = window.Globalbridge?.debug?.getSession?.()
  let hadOauthError = false
  try { hadOauthError = !!sessionStorage.getItem('auth0_last_error') } catch { hadOauthError = false }
  if (autoLogin && !session && !hadOauthError) {
    try {
      console.log('[Auth0] Auto-login enabled, redirecting to Auth0')
      await Auth0Client.login()
    } catch (e) {
      console.error('[Auth0] Auto-login failed:', e)
    }
  }
})

// Phoenix Channels Integration

/**
 * Initialize Phoenix Socket
 */
if (app.ports && app.ports.initSocket) {
  app.ports.initSocket.subscribe(({ endpoint, token }) => {
    try {
      PhoenixAdapter.initSocket(endpoint, token)
      console.log('[Phoenix] Socket initialized')
    } catch (error) {
      console.error('[Phoenix] Failed to initialize socket:', error)
    }
  })
}

/**
 * Join a Phoenix Channel
 */
if (app.ports && app.ports.joinChannel) {
  app.ports.joinChannel.subscribe(({ topic, params }) => {
    try {
      PhoenixAdapter.joinChannel(topic, params)
    } catch (error) {
      console.error('[Phoenix] Failed to join channel:', topic, error)
    }
  })
}

/**
 * Leave a Phoenix Channel
 */
if (app.ports && app.ports.leaveChannel) {
  app.ports.leaveChannel.subscribe((topic) => {
    try {
      PhoenixAdapter.leaveChannel(topic)
    } catch (error) {
      console.error('[Phoenix] Failed to leave channel:', topic, error)
    }
  })
}

/**
 * Send message to a channel
 */
if (app.ports && app.ports.sendChannelMessage) {
  app.ports.sendChannelMessage.subscribe(({ topic, event, payload }) => {
    try {
      PhoenixAdapter.sendMessage(topic, event, payload)
    } catch (error) {
      console.error('[Phoenix] Failed to send message:', topic, event, error)
    }
  })
}

// Auth0 Integration

/**
 * Handle Auth0 login request
 */
if (app.ports && app.ports.auth0Login) {
  app.ports.auth0Login.subscribe(async () => {
    try {
      console.log('[Auth0] Login requested by Elm')
      await Auth0Client.login()
      // After login, Auth0 will redirect back to the app
      // The redirect will be handled in initAuth0()
    } catch (error) {
      console.error('[Auth0] Login failed:', error)
      if (app.ports && app.ports.onAuth0LoginError) {
        app.ports.onAuth0LoginError.send(error.message || 'Login failed')
      }
    }
  })
}

/**
 * Handle Auth0 logout request
 */
if (app.ports && app.ports.auth0Logout) {
  app.ports.auth0Logout.subscribe(async () => {
    try {
      console.log('[Auth0] Logout requested by Elm')
      await Auth0Client.logout()
      // Auth0 will redirect to the app after logout
    } catch (error) {
      console.error('[Auth0] Logout failed:', error)
    }
  })
}

// Check for Auth0 login redirect on startup
async function checkAuth0Redirect() {
  try {
    // If Auth0 returned an error in the query string, surface it and clean the URL
    const params = new URLSearchParams(window.location.search)
    const oauthError = params.get('error')
    const oauthErrorDescription = params.get('error_description')

    if (oauthError) {
      const message = `${oauthError}: ${decodeURIComponent(oauthErrorDescription || '')}`.trim()
      if (app.ports && app.ports.onAuth0LoginError) {
        app.ports.onAuth0LoginError.send(message || 'Authentication failed')
      }
      // Mark that an OAuth error occurred to avoid auto-login loops
      try { sessionStorage.setItem('auth0_last_error', message || oauthError) } catch {}
      // Clean up URL
      window.history.replaceState({}, document.title, window.location.pathname)
      return
    }

    await Auth0Client.initAuth0()
    
    // If we just completed Auth0 login, get session data
    if (await Auth0Client.isAuthenticated()) {
      const sessionData = await Auth0Client.getSessionData()
      
      if (sessionData && app.ports && app.ports.onAuth0LoginComplete) {
        console.log('[Auth0] Login complete, sending session to Elm')
        app.ports.onAuth0LoginComplete.send(sessionData)
      }
    }
  } catch (error) {
    console.error('[Auth0] Failed to check redirect:', error)
  }
}

checkAuth0Redirect()

// Development utilities
if (import.meta.env.DEV) {
  window.Globalbridge = {
    debug: {
      app,
      clearSession: () => {
        localStorage.removeItem(SESSION_KEY)
        localStorage.removeItem(TOKEN_EXPIRY_KEY)
        console.log('[Debug] Session cleared')
      },
      getSession: () => {
        const session = localStorage.getItem(SESSION_KEY)
        return session ? JSON.parse(session) : null
      },
      phoenix: {
        isConnected: () => PhoenixAdapter.isConnected(),
        getChannels: () => PhoenixAdapter.getActiveChannels(),
        disconnect: () => PhoenixAdapter.disconnect()
      },
      insertEvent: (event) => {
        console.log('[Debug] Event:', event)
      }
    }
  }

  console.log('[Debug] Developer utilities available at window.Globalbridge.debug')
}
