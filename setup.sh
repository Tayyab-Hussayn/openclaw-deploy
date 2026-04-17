#!/usr/bin/env bash
set -e

OPENCLAW_CONFIG="$HOME/.openclaw"
OPENCLAW_WORKSPACE="$HOME/openclaw/workspace"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== OpenClaw Setup ==="

# 1. Create config dir
mkdir -p "$OPENCLAW_CONFIG"

# 2. Copy openclaw.json if it doesn't exist yet
if [ ! -f "$OPENCLAW_CONFIG/openclaw.json" ]; then
  cp "$SCRIPT_DIR/config/openclaw.json" "$OPENCLAW_CONFIG/openclaw.json"
  echo "[+] Copied config/openclaw.json → $OPENCLAW_CONFIG/openclaw.json"
else
  echo "[~] $OPENCLAW_CONFIG/openclaw.json already exists, skipping (delete it to reset)"
fi

# 3. Generate a random gateway token (replace the placeholder)
CURRENT_TOKEN=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG/openclaw.json') as f:
    d = json.load(f)
print(d.get('gateway', {}).get('auth', {}).get('token', ''))
")

if [ "$CURRENT_TOKEN" = "CHANGE_ME_USE_SETUP_SH_TO_AUTO_GENERATE" ]; then
  NEW_TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(24))")
  python3 -c "
import json
with open('$OPENCLAW_CONFIG/openclaw.json') as f:
    d = json.load(f)
d['gateway']['auth']['token'] = '$NEW_TOKEN'
with open('$OPENCLAW_CONFIG/openclaw.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  echo "[+] Generated gateway auth token: $NEW_TOKEN"
  echo "    Save this token — you'll need it to connect clients."
fi

# 4. Set up workspace
mkdir -p "$OPENCLAW_WORKSPACE/.openclaw"

for file in AGENTS.md BOOTSTRAP.md HEARTBEAT.md IDENTITY.md SOUL.md TOOLS.md USER.md; do
  if [ ! -f "$OPENCLAW_WORKSPACE/$file" ]; then
    cp "$SCRIPT_DIR/default-workspace/$file" "$OPENCLAW_WORKSPACE/$file"
    echo "[+] Copied $file → $OPENCLAW_WORKSPACE/$file"
  fi
done

if [ ! -f "$OPENCLAW_WORKSPACE/.openclaw/workspace-state.json" ]; then
  cp "$SCRIPT_DIR/default-workspace/.openclaw/workspace-state.json" "$OPENCLAW_WORKSPACE/.openclaw/workspace-state.json"
fi

# 5. Copy .env if not present
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
  echo "[+] Created .env from .env.example"
fi

echo ""
echo "=== Done! ==="
echo ""
echo "Next steps:"
echo "  1. Make sure Ollama is running on your host (ollama serve)"
echo "  2. Run:  docker compose up -d"
echo "  3. Open: http://localhost:18789"
echo ""
echo "Your gateway token is stored in $OPENCLAW_CONFIG/openclaw.json"
echo "  cat $OPENCLAW_CONFIG/openclaw.json | python3 -c \"import json,sys; print(json.load(sys.stdin)['gateway']['auth']['token'])\""
