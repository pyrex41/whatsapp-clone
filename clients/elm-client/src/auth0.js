/**
 * Auth0 Integration for Elm Client
 * 
 * Provides Auth0 authentication via JavaScript ports
 */

import { createAuth0Client } from '@auth0/auth0-spa-js'

let auth0Client = null
let isInitialized = false

// Auth0 Configuration
// Note: SPA apps MUST NOT include client secrets. Use only public values here.
const AUTH0_DOMAIN = import.meta.env.VITE_AUTH0_DOMAIN || 'dev-1672riu03fjuf7so.us.auth0.com'
const AUTH0_CLIENT_ID = import.meta.env.VITE_AUTH0_CLIENT_ID || '9rodqnNHxJxghoDbYFmDVyXIytKIHzdE'
const AUTH0_AUDIENCE = import.meta.env.VITE_AUTH0_AUDIENCE || 'globalbridge-api'
const AUTH0_REDIRECT_URI = import.meta.env.VITE_AUTH0_REDIRECT_URI || window.location.origin

const AUTH0_CONFIG = {
  domain: AUTH0_DOMAIN,
  clientId: AUTH0_CLIENT_ID,
  authorizationParams: {
    audience: AUTH0_AUDIENCE,
    scope: 'openid profile email offline_access',
    redirect_uri: AUTH0_REDIRECT_URI
  },
  cacheLocation: 'localstorage',
  useRefreshTokens: true
}

/**
 * Initialize Auth0 client
 */
export async function initAuth0() {
  if (isInitialized) {
    return auth0Client
  }

  try {
    console.log('[Auth0] Initializing client...')
    auth0Client = await createAuth0Client(AUTH0_CONFIG)
    isInitialized = true
    console.log('[Auth0] Client initialized successfully')
    
    // Check if returning from Auth0 login redirect
    const query = window.location.search
    if (query.includes('code=') && query.includes('state=')) {
      console.log('[Auth0] Handling redirect callback...')
      await auth0Client.handleRedirectCallback()
      
      // Clean up URL
      window.history.replaceState({}, document.title, window.location.pathname)
      
      console.log('[Auth0] Redirect handled successfully')
    }
    
    return auth0Client
  } catch (error) {
    console.error('[Auth0] Initialization failed:', error)
    throw error
  }
}

/**
 * Login with Auth0 (redirects to Auth0 login page)
 */
export async function login() {
  try {
    const client = await initAuth0()
    console.log('[Auth0] Starting login flow...')
    
    await client.loginWithRedirect({
      authorizationParams: {
        ...AUTH0_CONFIG.authorizationParams
      }
    })
  } catch (error) {
    console.error('[Auth0] Login failed:', error)
    throw error
  }
}

/**
 * Logout from Auth0
 */
export async function logout() {
  try {
    const client = await initAuth0()
    console.log('[Auth0] Logging out...')
    
    await client.logout({
      logoutParams: {
        returnTo: window.location.origin
      }
    })
  } catch (error) {
    console.error('[Auth0] Logout failed:', error)
    throw error
  }
}

/**
 * Check if user is authenticated
 */
export async function isAuthenticated() {
  try {
    const client = await initAuth0()
    const authenticated = await client.isAuthenticated()
    console.log('[Auth0] Authentication status:', authenticated)
    return authenticated
  } catch (error) {
    console.error('[Auth0] Failed to check authentication:', error)
    return false
  }
}

/**
 * Get current access token
 */
export async function getAccessToken() {
  try {
    const client = await initAuth0()
    
    if (!await client.isAuthenticated()) {
      console.log('[Auth0] Not authenticated, no token available')
      return null
    }
    
    const token = await client.getTokenSilently()
    console.log('[Auth0] Got access token')
    return token
  } catch (error) {
    console.error('[Auth0] Failed to get token:', error)
    return null
  }
}

/**
 * Get current user information
 */
export async function getUser() {
  try {
    const client = await initAuth0()
    
    if (!await client.isAuthenticated()) {
      return null
    }
    
    const user = await client.getUser()
    console.log('[Auth0] Got user:', user)
    return user
  } catch (error) {
    console.error('[Auth0] Failed to get user:', error)
    return null
  }
}

/**
 * Get session data for Elm
 */
export async function getSessionData() {
  try {
    const authenticated = await isAuthenticated()
    
    if (!authenticated) {
      return null
    }
    
    const [token, user] = await Promise.all([
      getAccessToken(),
      getUser()
    ])
    
    if (!token || !user) {
      return null
    }
    
    return {
      accessToken: token,
      refreshToken: '', // Auth0 handles refresh automatically
      userId: user.sub,
      username: user.name || user.nickname || user.email?.split('@')[0] || 'User',
      email: user.email
    }
  } catch (error) {
    console.error('[Auth0] Failed to get session data:', error)
    return null
  }
}
