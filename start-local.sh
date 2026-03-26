#!/bin/bash
# TradingGoose Local Development Startup Script
# Starts: SearxNG, Perplefina, Cloudflare Tunnel (auto-configures Supabase), Frontend

set -e

TRADING_DIR="$(cd "$(dirname "$0")" && pwd)"
PERPLEFINA_DIR="$(dirname "$TRADING_DIR")/Perplefina"
TUNNEL_LOG="/tmp/cloudflared-tradinggoose.log"

echo "=== TradingGoose Local Startup ==="
echo ""

# 1. Start SearxNG (Docker) if not running
if ! docker ps --format '{{.Names}}' | grep -q searxng; then
  echo "🔍 Starting SearxNG on port 4000..."
  (cd "$PERPLEFINA_DIR/searxng" && docker compose up -d)
else
  echo "✅ SearxNG already running on port 4000"
fi

# 2. Check Perplefina config
if grep -q "YOUR_.*_KEY_HERE" "$PERPLEFINA_DIR/config.toml" 2>/dev/null; then
  echo "❌ ERROR: Perplefina config.toml still has placeholder API keys!"
  echo "   Edit: $PERPLEFINA_DIR/config.toml"
  exit 1
fi

# 3. Start Perplefina if not running
if ! lsof -i :3000 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "🧠 Starting Perplefina on port 3000..."
  (cd "$PERPLEFINA_DIR" && npm run start > /tmp/perplefina.log 2>&1 &)
  echo "   Waiting for Perplefina to start..."
  for i in $(seq 1 15); do
    if curl -s -m 2 -o /dev/null http://localhost:3000 2>/dev/null; then
      echo "✅ Perplefina ready on port 3000"
      break
    fi
    if [ "$i" -eq 10 ]; then
      echo "   Still waiting... building might be needed"
      (cd "$PERPLEFINA_DIR" && npm run build >> /tmp/perplefina.log 2>&1 && npm run start >> /tmp/perplefina.log 2>&1 &)
    fi
    sleep 2
  done
  if ! curl -s -m 2 -o /dev/null http://localhost:3000 2>/dev/null; then
    echo "❌ Perplefina failed to start. Check /tmp/perplefina.log"
    exit 1
  fi
else
  echo "✅ Perplefina already running on port 3000"
fi

# 4. Kill any existing tunnel
pkill -f "cloudflared tunnel" 2>/dev/null || true
sleep 1

# 5. Start Cloudflare Tunnel and auto-extract URL
echo "🌐 Starting Cloudflare Tunnel..."
rm -f "$TUNNEL_LOG"
cloudflared tunnel --url http://localhost:3000 2>"$TUNNEL_LOG" &
TUNNEL_PID=$!

# Wait for the tunnel URL to appear in logs
TUNNEL_URL=""
for i in $(seq 1 20); do
  TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | head -1)
  if [ -n "$TUNNEL_URL" ]; then
    break
  fi
  sleep 1
done

if [ -z "$TUNNEL_URL" ]; then
  echo "❌ Failed to get tunnel URL after 20s. Check $TUNNEL_LOG"
  kill $TUNNEL_PID 2>/dev/null
  exit 1
fi

echo "✅ Tunnel ready: $TUNNEL_URL"

# 6. Auto-update Supabase secret with tunnel URL
echo "🔧 Updating Supabase PERPLEFINA_API_URL..."
(cd "$TRADING_DIR" && supabase secrets set "PERPLEFINA_API_URL=$TUNNEL_URL" 2>&1 | grep -v "new version")
echo "✅ Supabase secret updated"

# 7. Start Frontend
echo ""
echo "🚀 Starting TradingGoose frontend on port 5173..."
echo ""
echo "============================================"
echo "  Everything is running!"
echo ""
echo "  Frontend:   http://localhost:5173"
echo "  Perplefina: http://localhost:3000"
echo "  Tunnel:     $TUNNEL_URL"
echo "  SearxNG:    http://localhost:4000"
echo ""
echo "  Press Ctrl+C to stop everything"
echo "============================================"
echo ""

# Cleanup on exit: kill tunnel and perplefina
cleanup() {
  echo ""
  echo "🛑 Shutting down..."
  kill $TUNNEL_PID 2>/dev/null
  pkill -f "next start" 2>/dev/null
  echo "✅ Stopped. SearxNG Docker container left running."
}
trap cleanup EXIT INT TERM

# Run Vite in foreground (Ctrl+C stops everything)
cd "$TRADING_DIR" && npx vite --port 5173
