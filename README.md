# OpenClaw — Self-Hosted AI Gateway

Run your own OpenClaw instance with pre-configured Ollama cloud models. One script handles everything — Docker, Ollama, config, and startup.

**Supported platforms:** Linux (Ubuntu, Debian, Arch, Fedora) · WSL2

---

## Setup (3 steps)

### Step 1 — Clone the repo

```bash
git clone https://github.com/Tayyab-Hussayn/openclaw-deploy
cd openclaw-deploy
```

### Step 2 — Run setup

```bash
chmod +x setup.sh
./setup.sh
```

This single command handles everything automatically:
- Installs Docker, Docker Compose, and Ollama if missing
- Generates a unique login token for your instance
- Creates all config files with correct paths
- Pulls the OpenClaw image and starts the containers

> **Note:** You may be asked for your `sudo` password during installation.

### Step 3 — Open the dashboard

When setup finishes, you will see:

```
══════════════════════════════════════════
  OpenClaw is running!
══════════════════════════════════════════

  URL:    http://localhost:18789
  Token:  a3f9c2e1b7d4...
```

Open the URL in your browser and paste the token to log in.

**Forgot your token?** Run this anytime:
```bash
./info.sh
```

---

## Configure OpenClaw (channels, models, plugins)

After setup, run the interactive setup bridge:

```bash
chmod +x onboard.sh
./onboard.sh
```

You get a prompt where you type what you want to do:

```
openclaw> connect whatsapp      ← scan QR code to link your WhatsApp
openclaw> connect telegram      ← connect a Telegram bot
openclaw> models                ← add/change AI model providers
openclaw> configure             ← full interactive configuration wizard
openclaw> status                ← check what's connected
openclaw> doctor                ← run health checks
openclaw> tui                   ← open the full terminal UI
openclaw> help                  ← see all commands
```

All actual setup screens, QR codes, and prompts are handled by OpenClaw itself — `onboard.sh` just launches the right command for you.

---

## WSL2 Users (accessing from Windows Chrome)

Your OpenClaw runs inside WSL2 but is accessible from your Windows browser.

**Try this first:**
```
http://localhost:18789
```

**If localhost doesn't work**, get your WSL IP and use that:
```bash
hostname -I | awk '{print $1}'
# then open: http://<that-ip>:18789
```

The `./info.sh` script prints both URLs automatically when it detects WSL.

---

## Included Models

All models connect through Ollama and are free to use:

| Model | Type |
|-------|------|
| kimi-k2.5:cloud | Text + Vision |
| qwen3.5:cloud | Text + Vision |
| deepseek-v3.2:cloud | Text |
| gemini-3-flash-preview:latest | Text + Vision |
| glm-5.1:cloud | Text |
| minimax-m2.7:cloud | Text |
| qwen2.5-coder:7b | Code |
| and more... | |

---

## Managing Your Instance

**Stop:**
```bash
docker compose down
```

**Start again:**
```bash
docker compose up -d
```

**Update to latest version:**
```bash
docker pull ghcr.io/openclaw/openclaw:latest
docker compose up -d
```

**Re-run setup** (safe to run again — skips what's already done):
```bash
./setup.sh
```

---

## Configuration

Your config lives at `~/.openclaw/openclaw.json`. Edit it to customize your instance.

**Enable WhatsApp:**
```json
"channels": {
  "whatsapp": {
    "enabled": true,
    "dmPolicy": "allowlist",
    "allowFrom": ["+1234567890"]
  }
}
```

**Add Brave Search:**
```json
"plugins": {
  "entries": {
    "brave": {
      "enabled": true,
      "config": {
        "webSearch": { "apiKey": "YOUR_BRAVE_API_KEY" }
      }
    }
  }
}
```

After any config change, restart:
```bash
docker compose restart
```

**Change ports:** Edit `.env` in the repo folder.

---

## Ports

| Port  | Service        |
|-------|----------------|
| 18789 | Dashboard / API |
| 18790 | Bridge          |

---

## Troubleshooting

**Models not responding?**
Ollama may not be running. Start it:
```bash
ollama serve
```

**Permission denied on Docker?**
Log out and back in — your user was added to the `docker` group during setup.

**Port already in use?**
Find what's using it and stop it:
```bash
ss -tlnp | grep 18789
```

**Check container logs:**
```bash
docker compose logs -f
```
