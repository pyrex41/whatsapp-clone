// JavaScript entry point for Elm application
import { Elm } from './Main.elm'
import * as PhoenixAdapter from './phoenixAdapter.js'

// Get CSRF token from meta tag (will be set by Phoenix)
const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || ''

// Get API URL from environment or default to localhost
const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:4000'

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
        email: sessionData.email,
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

      console.log('[Session] Stored session for user:', sessionData.email)
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
 * Restore session on app startup
 */
function restoreSession() {
  try {
    const sessionJson = localStorage.getItem(SESSION_KEY)
    const expiryStr = localStorage.getItem(TOKEN_EXPIRY_KEY)

    if (!sessionJson || !expiryStr) {
      // No stored session
      if (app.ports && app.ports.onSessionRestored) {
        app.ports.onSessionRestored.send(null)
      }
      return
    }

    const expiry = parseInt(expiryStr, 10)
    if (Date.now() > expiry) {
      // Session expired
      console.log('[Session] Stored session expired')
      localStorage.removeItem(SESSION_KEY)
      localStorage.removeItem(TOKEN_EXPIRY_KEY)
      if (app.ports && app.ports.onSessionRestored) {
        app.ports.onSessionRestored.send(null)
      }
      return
    }

    const sessionData = JSON.parse(sessionJson)
    console.log('[Session] Restored session for user:', sessionData.email)

    if (app.ports && app.ports.onSessionRestored) {
      app.ports.onSessionRestored.send(sessionData)
    }
  } catch (error) {
    console.error('[Session] Failed to restore session:', error)
    if (app.ports && app.ports.onSessionRestored) {
      app.ports.onSessionRestored.send(null)
    }
  }
}

// Restore session on startup
restoreSession()

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
