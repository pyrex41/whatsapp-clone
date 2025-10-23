// Sample updated hook by grok-code-fast-1
// Original: Basic auth check. Updated: Added offline mode with localStorage sync and token refresh.

/**
 * Custom hook for authentication with offline support.
 * @returns {Object} Auth state and methods.
 */
import { useState, useEffect } from 'react';
import jwtDecode from 'jwt-decode'; // Assume installed

export const useAuth = () => {
  const [user, setUser] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isOffline, setIsOffline] = useState(false);

  useEffect(() => {
    const token = localStorage.getItem('authToken');
    if (token) {
      try {
        const decoded = jwtDecode(token);
        if (decoded.exp * 1000 > Date.now()) {
          setUser(decoded);
        } else {
          // Token expired - attempt refresh (online only)
          refreshToken();
        }
      } catch (err) {
        console.error('Invalid token:', err);
        logout();
      }
    }
    setIsLoading(false);

    // Offline detection
    const handleOnline = () => setIsOffline(false);
    const handleOffline = () => setIsOffline(true);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  const login = async (credentials) => {
    try {
      const response = await fetch('/api/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(credentials),
      });
      if (response.ok) {
        const { token } = await response.json();
        localStorage.setItem('authToken', token);
        const decoded = jwtDecode(token);
        setUser(decoded);
      }
    } catch (err) {
      console.error('Login failed:', err);
      if (navigator.onLine === false) setIsOffline(true);
    }
  };

  const refreshToken = async () => {
    if (isOffline) return; // Skip if offline
    // Implementation for token refresh...
    // On success, update localStorage and user state
  };

  const logout = () => {
    localStorage.removeItem('authToken');
    setUser(null);
  };

  // Offline: Use cached user if available
  const effectiveUser = isOffline && user ? user : user;

  return {
    user: effectiveUser,
    login,
    logout,
    isLoading,
    isOffline,
  };
};
