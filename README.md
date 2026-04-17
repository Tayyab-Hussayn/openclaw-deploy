# OpenClaw — Self-Hosted AI Gateway

Pre-configured Docker deployment of OpenClaw with Ollama cloud models. Clone, run setup, and you're live — no manual onboarding required.

## What's included

- Full Ollama cloud model list (kimi-k2.5, deepseek-v3.2, qwen3.5, gemini-3-flash, and more)
- Pre-configured workspace with agent persona files
- Auto-generated gateway auth token on first run

## Requirements

- Docker + Docker Compose
- Ollama running on your host machine (`ollama serve`)
- Python 3 (for setup script)

## Quick Start

```bash
git clone <this-repo-url>
cd openclaw

chmod +x setup.sh
./setup.sh

docker compose up -d
```

Then open **http://localhost:18789** in your browser.

Your gateway token will be printed during setup — save it. You need it to connect.

## What setup.sh does

1. Creates `~/.openclaw/` and copies the config
2. Generates a unique random gateway auth token for you
3. Sets up the default workspace files at `~/openclaw/workspace/`
4. Creates `.env` from `.env.example`

## Configuration

Edit `~/.openclaw/openclaw.json` after setup to:
- Add/remove Ollama models
- Enable WhatsApp channel (add your number to `channels.whatsapp.allowFrom`, set `enabled: true`)
- Add Brave search API key under `plugins.entries.brave`
- Change gateway bind (`loopback` = localhost only, `lan` = accessible on network)

## Ports

| Port  | Service         |
|-------|----------------|
| 18789 | Gateway HTTP   |
| 18790 | Bridge         |

To change ports, edit `.env`.

## Connecting to WhatsApp

After setup, edit `~/.openclaw/openclaw.json`:

```json
"channels": {
  "whatsapp": {
    "enabled": true,
    "dmPolicy": "allowlist",
    "allowFrom": ["+1234567890"]
  }
}
```

Then restart: `docker compose restart`

## Updating

```bash
docker compose pull
docker compose up -d
```
