/**
 * Phoenix Channels JavaScript Adapter
 *
 * Provides bidirectional communication between Elm and Phoenix Channels
 * via JavaScript interop (ports).
 */

import { Socket } from 'phoenix'

// Connection state
let socket = null
let channels = new Map() // topic -> channel instance
let reconnectAttempts = 0
let reconnectTimer = null
let heartbeatInterval = null

// Configuration
const INITIAL_RECONNECT_DELAY = 1000 // 1 second
const MAX_RECONNECT_DELAY = 30000 // 30 seconds
const HEARTBEAT_INTERVAL = 30000 // 30 seconds

/**
 * Initialize Phoenix Socket with authentication
 */
export function initSocket(endpoint, token) {
  if (socket) {
    socket.disconnect()
  }

  socket = new Socket(endpoint, {
    params: { token },
    logger: (kind, msg, data) => {
      console.log(`[Phoenix ${kind}]`, msg, data)
    },
    reconnectAfterMs: (tries) => {
      // Exponential backoff with max
      const delay = Math.min(INITIAL_RECONNECT_DELAY * Math.pow(2, tries), MAX_RECONNECT_DELAY)
      console.log(`[Phoenix] Reconnect attempt ${tries + 1} in ${delay}ms`)
      return delay
    }
  })

  // Socket event handlers
  socket.onOpen(() => {
    console.log('[Phoenix] Socket connected')
    reconnectAttempts = 0
    startHeartbeat()

    // Notify Elm about connection
    if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onSocketConnected) {
      window.elmApp.ports.onSocketConnected.send(true)
    }
  })

  socket.onError((error) => {
    console.error('[Phoenix] Socket error:', error)

    if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onSocketError) {
      window.elmApp.ports.onSocketError.send(error.message || 'Socket error')
    }
  })

  socket.onClose(() => {
    console.log('[Phoenix] Socket closed')
    stopHeartbeat()

    if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onSocketConnected) {
      window.elmApp.ports.onSocketConnected.send(false)
    }
  })

  socket.connect()
  return socket
}

/**
 * Join a Phoenix Channel
 */
export function joinChannel(topic, params = {}) {
  if (!socket) {
    console.error('[Phoenix] Cannot join channel: socket not initialized')
    return null
  }

  // Check if already subscribed
  if (channels.has(topic)) {
    console.log(`[Phoenix] Already subscribed to ${topic}`)
    return channels.get(topic)
  }

  const channel = socket.channel(topic, params)

  // Channel event handlers
  channel.on('new_msg', (payload) => {
    console.log('[Phoenix] New message:', payload)

    if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onChannelMessage) {
      window.elmApp.ports.onChannelMessage.send({
        topic,
        event: 'new_msg',
        payload
      })
    }
  })

  channel.on('user_typing', (payload) => {
    if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onChannelMessage) {
      window.elmApp.ports.onChannelMessage.send({
        topic,
        event: 'user_typing',
        payload
      })
    }
  })

  channel.on('presence_state', (payload) => {
    if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onChannelMessage) {
      window.elmApp.ports.onChannelMessage.send({
        topic,
        event: 'presence_state',
        payload
      })
    }
  })

  channel.on('presence_diff', (payload) => {
    if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onChannelMessage) {
      window.elmApp.ports.onChannelMessage.send({
        topic,
        event: 'presence_diff',
        payload
      })
    }
  })

  // Join the channel
  channel.join()
    .receive('ok', (resp) => {
      console.log(`[Phoenix] Joined ${topic}`, resp)

      if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onChannelJoined) {
        window.elmApp.ports.onChannelJoined.send({ topic, data: resp })
      }
    })
    .receive('error', (resp) => {
      console.error(`[Phoenix] Failed to join ${topic}:`, resp)

      if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onChannelError) {
        window.elmApp.ports.onChannelError.send({
          topic,
          error: resp.reason || 'Failed to join channel'
        })
      }
    })
    .receive('timeout', () => {
      console.error(`[Phoenix] Join timeout for ${topic}`)

      if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onChannelError) {
        window.elmApp.ports.onChannelError.send({
          topic,
          error: 'Join timeout'
        })
      }
    })

  channels.set(topic, channel)
  return channel
}

/**
 * Leave a Phoenix Channel
 */
export function leaveChannel(topic) {
  const channel = channels.get(topic)

  if (!channel) {
    console.warn(`[Phoenix] Channel ${topic} not found`)
    return
  }

  channel.leave()
    .receive('ok', () => {
      console.log(`[Phoenix] Left ${topic}`)
      channels.delete(topic)

      if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onChannelLeft) {
        window.elmApp.ports.onChannelLeft.send(topic)
      }
    })
}

/**
 * Send message to a channel
 */
export function sendMessage(topic, event, payload) {
  const channel = channels.get(topic)

  if (!channel) {
    console.error(`[Phoenix] Cannot send to ${topic}: not subscribed`)
    return Promise.reject(new Error('Not subscribed to channel'))
  }

  return channel.push(event, payload)
    .receive('ok', (resp) => {
      console.log(`[Phoenix] Message sent to ${topic}:`, event, resp)
    })
    .receive('error', (resp) => {
      console.error(`[Phoenix] Failed to send to ${topic}:`, event, resp)

      if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onChannelError) {
        window.elmApp.ports.onChannelError.send({
          topic,
          error: `Failed to send ${event}: ${resp.reason || 'unknown error'}`
        })
      }
    })
    .receive('timeout', () => {
      console.error(`[Phoenix] Timeout sending to ${topic}:`, event)

      if (window.elmApp && window.elmApp.ports && window.elmApp.ports.onChannelError) {
        window.elmApp.ports.onChannelError.send({
          topic,
          error: `Timeout sending ${event}`
        })
      }
    })
}

/**
 * Start heartbeat/keepalive
 */
function startHeartbeat() {
  if (heartbeatInterval) {
    clearInterval(heartbeatInterval)
  }

  heartbeatInterval = setInterval(() => {
    if (socket && socket.isConnected()) {
      // Phoenix Socket has built-in heartbeat, but we can add custom ping
      console.log('[Phoenix] Heartbeat ping')
    } else {
      console.warn('[Phoenix] Heartbeat: socket not connected')
    }
  }, HEARTBEAT_INTERVAL)
}

/**
 * Stop heartbeat
 */
function stopHeartbeat() {
  if (heartbeatInterval) {
    clearInterval(heartbeatInterval)
    heartbeatInterval = null
  }
}

/**
 * Update socket token (for token refresh)
 */
export function updateToken(newToken) {
  if (!socket) {
    console.error('[Phoenix] Cannot update token: socket not initialized')
    return
  }

  // Disconnect and reconnect with new token
  const wasConnected = socket.isConnected()
  const activeTopics = Array.from(channels.keys())

  socket.disconnect()
  socket = null
  channels.clear()

  // Reinitialize with new token
  initSocket(socket.endPointURL(), newToken)

  // Rejoin active channels
  if (wasConnected) {
    activeTopics.forEach(topic => {
      joinChannel(topic)
    })
  }
}

/**
 * Disconnect socket and cleanup
 */
export function disconnect() {
  stopHeartbeat()

  // Leave all channels
  channels.forEach((channel, topic) => {
    channel.leave()
  })
  channels.clear()

  if (socket) {
    socket.disconnect()
    socket = null
  }

  console.log('[Phoenix] Disconnected and cleaned up')
}

/**
 * Get socket connection status
 */
export function isConnected() {
  return socket && socket.isConnected()
}

/**
 * Get active channels
 */
export function getActiveChannels() {
  return Array.from(channels.keys())
}
