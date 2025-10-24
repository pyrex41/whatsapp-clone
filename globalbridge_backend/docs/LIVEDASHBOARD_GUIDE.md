# Phoenix LiveDashboard Access Guide

## 🎯 Quick Access

**URL:** http://localhost:4000/dev/dashboard

**Note:** Only available in development mode (not production)

---

## 🚀 Starting the Server

```bash
cd globalbridge_backend
mix phx.server
```

Then open your browser to: **http://localhost:4000/dev/dashboard**

---

## 📊 Dashboard Features

### 1. **Home**
- System information
- Phoenix version
- Elixir/OTP version
- Uptime

### 2. **Metrics**
- Real-time metrics visualization
- Request/response times
- Database query times
- Phoenix Channel connections
- Custom telemetry metrics

### 3. **Request Logger**
- Live request monitoring
- HTTP requests in real-time
- Response times
- Status codes

### 4. **Applications**
- Application tree
- Loaded applications
- Dependencies

### 5. **Processes**
- All running processes
- Memory usage per process
- Message queue lengths
- Process information

### 6. **Ports**
- Active network ports
- Port information
- Connected endpoints

### 7. **Sockets**
- Phoenix Channel sockets
- WebSocket connections
- Active user channels
- Real-time connection monitoring

### 8. **ETS (Erlang Term Storage)**
- ETS tables
- Memory usage
- Table information
- Cached data inspection

### 9. **OS Data**
- CPU usage
- Memory usage
- Disk I/O
- System statistics

---

## 🔍 Monitoring Your App

### Watch Real-Time Connections
1. Go to **Sockets** tab
2. See active Phoenix Channel connections
3. Monitor `user:*` and `thread:*` channels
4. Track connection counts

### Monitor Performance
1. Go to **Metrics** tab
2. Watch Phoenix request duration
3. Check database query times
4. Monitor Ecto query counts

### Debug Process Issues
1. Go to **Processes** tab
2. Sort by memory or reductions
3. Click on a process to inspect
4. View process state and messages

### Check Database Queries
1. Enable query logging in dev.exs (already enabled)
2. Watch Request Logger for DB queries
3. Metrics show query timing

---

## 🎨 Custom Metrics

The dashboard displays metrics from `GlobalbridgeBackendWeb.Telemetry`:

- Phoenix endpoint metrics
- Ecto database metrics
- VM metrics
- Custom application metrics

---

## 📧 Bonus: Mailbox Preview

**URL:** http://localhost:4000/dev/mailbox

View emails sent by your application in development (using Swoosh.Adapters.Local).

---

## 🔒 Production Notes

**The LiveDashboard is disabled in production by default** for security reasons.

To enable in production, you would need to:
1. Add authentication (e.g., Plug.BasicAuth)
2. Restrict to admin users only
3. Use HTTPS
4. Update the router condition

Example (do not use without proper security):
```elixir
# In router.ex - DO NOT USE AS-IS IN PRODUCTION
scope "/admin" do
  pipe_through [:browser, :auth, :admin_only]
  live_dashboard "/dashboard", metrics: GlobalbridgeBackendWeb.Telemetry
end
```

---

## 🛠️ Troubleshooting

### Dashboard not loading?
1. Make sure server is running: `mix phx.server`
2. Check you're in development mode
3. Verify `dev_routes: true` in `config/dev.exs`
4. Clear browser cache

### No metrics showing?
1. Generate some traffic (make API requests)
2. Refresh the dashboard
3. Check Telemetry module exists

### Socket connections not showing?
1. Connect with iOS app or test client
2. Join channels via Phoenix socket
3. Refresh Sockets tab in dashboard

---

## 📚 Learn More

- [Phoenix LiveDashboard Docs](https://hexdocs.pm/phoenix_live_dashboard)
- [Telemetry Guide](https://hexdocs.pm/phoenix/telemetry.html)
- [Phoenix Metrics](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html#module-instrumentation)

---

## ✅ Quick Checklist

- [x] Dependency added to mix.exs
- [x] Routes configured in router.ex
- [x] dev_routes enabled in config/dev.exs
- [x] Telemetry module exists
- [x] Dependencies installed

**You're all set!** Start the server and visit http://localhost:4000/dev/dashboard
