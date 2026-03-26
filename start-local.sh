#!/bin/bash
# TradingGoose Local Development Startup Script
# Starts: SearxNG, Perplefina, Cloudflare Tunnel, Frontend

set -e

TRADING_DIR="$(cd "$(dirname "$0")" && pwd)"
PERPLEFINA_DIR="$(dirname "$TRADING_DIR")/Perplefina"

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
  (cd "$PERPLEFINA_DIR" && npm run start &)
  sleep 5
  if ! lsof -i :3000 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "   Building Perplefina first..."
    (cd "$PERPLEFINA_DIR" && npm run build && npm run start &)
    sleep 10
  fi
else
  echo "✅ Perplefina already running on port 3000"
fi

# 4. Start Cloudflare Tunnel
echo "🌐 Starting Cloudflare Tunnel for Perplefina..."
echo "   (Keep this terminal open — tunnel closes when you close it)"
echo ""
echo "   Once the tunnel URL appears below, run:"
echo "   cd $TRADING_DIR && supabase secrets set PERPLEFINA_API_URL=<tunnel-url>"
echo ""
echo "   Then open another terminal and run:"
echo "   cd $TRADING_DIR && npx vite --port 5173"
echo ""
echo "=== Tunnel starting... ==="
cloudflared tunnel --url http://localhost:3000
