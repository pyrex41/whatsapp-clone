# GlobalBridge Elm Web Client

Browser-based client for GlobalBridge Messenger, built with Elm 0.19 and Vite.

## Quick Start

```bash
# Install dependencies
npm install

# Install Elm packages
npm run elm -- install

# Start development server
npm run dev
```

The client will be available at `http://localhost:3000` with hot reload enabled.

## Development

### Project Structure

```
elm-client/
├── src/
│   ├── Main.elm          # Entry point and app initialization
│   └── main.js           # JavaScript interop layer
├── public/
│   ├── index.html        # HTML entry point
│   └── styles.css        # Global styles
├── tests/                # Elm test files
├── elm.json              # Elm dependencies
├── package.json          # npm dependencies
└── vite.config.js        # Vite build configuration
```

### Available Scripts

- `npm run dev` - Start development server with hot reload
- `npm run build` - Build optimized production bundle
- `npm run preview` - Preview production build locally
- `npm run elm:make` - Compile Elm code manually
- `npm run elm:make:opt` - Compile with optimizations
- `npm test` - Run Elm tests

### Backend Integration

The Vite dev server proxies API requests to the Phoenix backend:
- `/api/*` → `http://localhost:4000/api/*`
- `/socket` → `ws://localhost:4000/socket` (WebSocket)

Production builds output to `globalbridge_backend/priv/static/elm/` for Phoenix static serving.

## Architecture

This client follows **The Elm Architecture (TEA)**:
- **Model**: Application state (immutable)
- **Update**: State transitions via messages
- **View**: Pure functions rendering HTML
- **Subscriptions**: External event streams (WebSocket, time, etc.)

### Key Features (Roadmap)

- ✅ Project scaffolding with Vite
- ⏳ Authentication (Guardian tokens)
- ⏳ Phoenix Channels integration
- ⏳ Thread list with real-time updates
- ⏳ Conversation view with optimistic sends
- ⏳ Bridge status panel
- ⏳ Developer debug utilities

## Testing

```bash
# Run Elm tests
npm test

# Run Cypress E2E tests (coming in Task 12)
npm run cypress:open
```

## Build for Production

```bash
npm run build
```

Optimized bundle will be output to `../../globalbridge_backend/priv/static/elm/` for Phoenix to serve.

## Developer Mode

In development, `window.Globalbridge.debug` is available for:
- Inserting test events
- Inspecting application state
- Triggering mock scenarios

## License

Proprietary - GlobalBridge Messenger
