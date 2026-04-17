#!/usr/bin/env bash
# OpenClaw Setup Script
# Supports: Ubuntu/Debian, Arch, Fedora/RHEL, WSL2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_CONFIG="$HOME/.openclaw"
OPENCLAW_WORKSPACE="$SCRIPT_DIR/workspace"   # always relative to repo

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}[*]${NC} $1"; }
ok()      { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
die()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
banner()  { echo -e "\n${BOLD}$1${NC}"; }

# ── Docker command (may be prefixed with sudo) ─────────────────────────────
DOCKER_CMD="docker"
COMPOSE_CMD=""

# ── 1. Detect environment ─────────────────────────────────────────────────────
banner "=== OpenClaw Setup ==="
echo ""

IS_WSL=false
if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
  IS_WSL=true
  info "WSL environment detected"
fi

# Detect distro for package manager
DISTRO="unknown"
PKG_MGR="unknown"
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO="${ID:-unknown}"
fi

if   command -v apt-get &>/dev/null; then PKG_MGR="apt"
elif command -v pacman  &>/dev/null; then PKG_MGR="pacman"
elif command -v dnf     &>/dev/null; then PKG_MGR="dnf"
elif command -v yum     &>/dev/null; then PKG_MGR="yum"
fi

info "Distro: $DISTRO | Package manager: $PKG_MGR | WSL: $IS_WSL"

# ── 2. Check / Install Docker ─────────────────────────────────────────────────
banner "── Checking Docker ──"

if ! command -v docker &>/dev/null; then
  warn "Docker not found. Installing..."

  case "$PKG_MGR" in
    apt)
      sudo apt-get update -qq
      sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release

      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
      sudo chmod a+r /etc/apt/keyrings/docker.gpg

      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/${DISTRO} $(lsb_release -cs) stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

      sudo apt-get update -qq
      sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
      ;;
    pacman)
      sudo pacman -Sy --noconfirm docker docker-compose
      ;;
    dnf)
      sudo dnf -y install dnf-plugins-core
      sudo dnf config-manager --add-repo \
        https://download.docker.com/linux/fedora/docker-ce.repo
      sudo dnf -y install docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
      ;;
    yum)
      sudo yum install -y yum-utils
      sudo yum-config-manager --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo
      sudo yum install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
      ;;
    *)
      die "Cannot auto-install Docker: unsupported package manager '$PKG_MGR'.\nInstall manually: https://docs.docker.com/engine/install/"
      ;;
  esac

  ok "Docker installed."
else
  ok "Docker is installed: $(docker --version 2>/dev/null | head -1)"
fi

# ── 3. Check / Install Docker Compose ────────────────────────────────────────
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
  ok "Docker Compose v2 available"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
  warn "Using legacy docker-compose v1. Consider upgrading to Docker Compose v2."
else
  warn "Docker Compose not found. Installing compose plugin..."
  case "$PKG_MGR" in
    apt)     sudo apt-get install -y -qq docker-compose-plugin ;;
    pacman)  sudo pacman -Sy --noconfirm docker-compose ;;
    dnf|yum) sudo "${PKG_MGR}" install -y docker-compose-plugin ;;
    *)
      # Fallback: install compose v2 binary manually
      COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
      sudo curl -fsSL \
        "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
        -o /usr/local/bin/docker-compose
      sudo chmod +x /usr/local/bin/docker-compose
      COMPOSE_CMD="docker-compose"
      ;;
  esac
  ok "Docker Compose installed."
  # Re-check after install
  if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  else
    COMPOSE_CMD="docker-compose"
  fi
fi

# ── 4. Start Docker daemon ────────────────────────────────────────────────────
banner "── Starting Docker daemon ──"

start_docker_daemon() {
  # Try systemd first
  if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
    sudo systemctl enable docker --now 2>/dev/null || true
    sudo systemctl start docker 2>/dev/null || true
  elif command -v service &>/dev/null; then
    # SysV init / WSL without systemd
    sudo service docker start 2>/dev/null || true
  else
    # Last resort: start dockerd directly (common in WSL minimal setups)
    warn "No init system found. Starting dockerd directly..."
    sudo dockerd > /tmp/dockerd.log 2>&1 &
  fi

  # Wait up to 20s for daemon to be ready
  local tries=0
  while ! docker info &>/dev/null 2>&1; do
    sleep 1
    tries=$((tries + 1))
    if [ "$tries" -ge 20 ]; then
      die "Docker daemon failed to start after 20s.\nCheck logs: /tmp/dockerd.log or 'sudo journalctl -u docker'"
    fi
  done
}

if ! docker info &>/dev/null 2>&1; then
  warn "Docker daemon is not running. Attempting to start..."
  start_docker_daemon
  ok "Docker daemon started."
else
  ok "Docker daemon is running."
fi

# ── 5. Fix Docker group permissions ──────────────────────────────────────────
if ! docker ps &>/dev/null 2>&1; then
  warn "User '$USER' cannot access Docker socket. Adding to docker group..."
  sudo usermod -aG docker "$USER"
  warn "Group change takes effect in a new shell. Using 'sudo docker' for this session."
  DOCKER_CMD="sudo docker"
  if [ "$COMPOSE_CMD" = "docker compose" ]; then
    COMPOSE_CMD="sudo docker compose"
  else
    COMPOSE_CMD="sudo docker-compose"
  fi
else
  ok "Docker permissions OK (no sudo needed)."
fi

# ── 6. Check Python3 or openssl (for token generation) ───────────────────────
banner "── Checking dependencies ──"

HAS_PYTHON3=false
HAS_JQ=false

if command -v python3 &>/dev/null; then
  HAS_PYTHON3=true
  ok "python3 found"
fi
if command -v jq &>/dev/null; then
  HAS_JQ=true
  ok "jq found"
fi

# Token generation: python3 > openssl > /dev/urandom
generate_token() {
  if $HAS_PYTHON3; then
    python3 -c "import secrets; print(secrets.token_hex(24))"
  elif command -v openssl &>/dev/null; then
    openssl rand -hex 24
  else
    cat /dev/urandom | tr -dc 'a-f0-9' | head -c 48
  fi
}

# JSON token extraction
get_current_token() {
  local file="$1"
  if $HAS_PYTHON3; then
    python3 -c "import json,sys; d=json.load(open('$file')); print(d.get('gateway',{}).get('auth',{}).get('token',''))"
  elif $HAS_JQ; then
    jq -r '.gateway.auth.token // ""' "$file"
  else
    # bare grep fallback
    grep -o '"token": *"[^"]*"' "$file" | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
  fi
}

# JSON token replacement
set_token_in_json() {
  local file="$1"
  local token="$2"
  if $HAS_PYTHON3; then
    python3 - "$file" "$token" <<'PYEOF'
import json, sys
path, tok = sys.argv[1], sys.argv[2]
with open(path) as f:
    d = json.load(f)
d['gateway']['auth']['token'] = tok
with open(path, 'w') as f:
    json.dump(d, f, indent=2)
PYEOF
  elif $HAS_JQ; then
    local tmp
    tmp=$(mktemp)
    jq --arg tok "$token" '.gateway.auth.token = $tok' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    # sed fallback — works for the known placeholder string
    sed -i "s/CHANGE_ME_USE_SETUP_SH_TO_AUTO_GENERATE/$token/g" "$file"
  fi
}

# ── 7. Check port availability ────────────────────────────────────────────────
banner "── Checking ports ──"

check_port() {
  local port="$1"
  if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | grep -q ":${port} " && return 0 || return 1
  elif command -v netstat &>/dev/null; then
    netstat -tlnp 2>/dev/null | grep -q ":${port} " && return 0 || return 1
  fi
  return 1  # can't check, assume free
}

if check_port 18789; then
  warn "Port 18789 is already in use. OpenClaw gateway may fail to start."
  warn "Check what's using it: ss -tlnp | grep 18789"
else
  ok "Port 18789 is free."
fi

if check_port 18790; then
  warn "Port 18790 is already in use. OpenClaw bridge may fail to start."
else
  ok "Port 18790 is free."
fi

# ── 8. Create ~/.openclaw config ──────────────────────────────────────────────
banner "── Setting up config ──"

mkdir -p "$OPENCLAW_CONFIG"

if [ ! -f "$OPENCLAW_CONFIG/openclaw.json" ]; then
  cp "$SCRIPT_DIR/config/openclaw.json" "$OPENCLAW_CONFIG/openclaw.json"
  ok "Copied openclaw.json → $OPENCLAW_CONFIG/openclaw.json"
else
  warn "Config already exists at $OPENCLAW_CONFIG/openclaw.json — skipping. Delete it to reset."
fi

# ── 9. Generate gateway auth token ───────────────────────────────────────────
CURRENT_TOKEN=$(get_current_token "$OPENCLAW_CONFIG/openclaw.json")

if [ "$CURRENT_TOKEN" = "CHANGE_ME_USE_SETUP_SH_TO_AUTO_GENERATE" ] || [ -z "$CURRENT_TOKEN" ]; then
  NEW_TOKEN=$(generate_token)
  set_token_in_json "$OPENCLAW_CONFIG/openclaw.json" "$NEW_TOKEN"
  ok "Generated gateway token: ${BOLD}$NEW_TOKEN${NC}"
  echo "    → Save this. You need it to log into the OpenClaw UI."
else
  ok "Gateway token already set."
fi

# ── 10. Set up workspace ──────────────────────────────────────────────────────
banner "── Setting up workspace ──"

mkdir -p "$OPENCLAW_WORKSPACE/.openclaw"

for file in AGENTS.md BOOTSTRAP.md HEARTBEAT.md IDENTITY.md SOUL.md TOOLS.md USER.md; do
  if [ ! -f "$OPENCLAW_WORKSPACE/$file" ]; then
    cp "$SCRIPT_DIR/default-workspace/$file" "$OPENCLAW_WORKSPACE/$file"
    ok "Copied $file"
  fi
done

if [ ! -f "$OPENCLAW_WORKSPACE/.openclaw/workspace-state.json" ]; then
  cp "$SCRIPT_DIR/default-workspace/.openclaw/workspace-state.json" \
     "$OPENCLAW_WORKSPACE/.openclaw/workspace-state.json"
fi

# ── 11. Write .env with absolute paths ───────────────────────────────────────
#  IMPORTANT: Docker Compose does NOT expand '~' in .env volume paths.
#  We must write real absolute paths here.
banner "── Writing .env ──"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  cat > "$SCRIPT_DIR/.env" <<EOF
OPENCLAW_CONFIG_DIR=${OPENCLAW_CONFIG}
OPENCLAW_WORKSPACE_DIR=${OPENCLAW_WORKSPACE}
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_BRIDGE_PORT=18790
OPENCLAW_GATEWAY_BIND=lan
EOF
  ok "Created .env with absolute paths"
else
  # Check if the existing .env still has the ~ placeholder and fix it
  if grep -q "~/" "$SCRIPT_DIR/.env"; then
    warn ".env contains '~/' paths — Docker won't expand these. Fixing..."
    sed -i "s|~/.openclaw|${OPENCLAW_CONFIG}|g" "$SCRIPT_DIR/.env"
    sed -i "s|~/openclaw/workspace|${OPENCLAW_WORKSPACE}|g" "$SCRIPT_DIR/.env"
    ok ".env paths updated to absolute."
  else
    ok ".env already exists."
  fi
fi

# ── 12. Check Ollama ──────────────────────────────────────────────────────────
banner "── Checking Ollama ──"

OLLAMA_OK=false
if curl -sf http://localhost:11434 &>/dev/null; then
  OLLAMA_OK=true
  ok "Ollama is running on localhost:11434"
elif curl -sf http://127.0.0.1:11434 &>/dev/null; then
  OLLAMA_OK=true
  ok "Ollama is running on 127.0.0.1:11434"
else
  warn "Ollama is NOT running on port 11434."
  warn "Models will not work until Ollama is started."
  if command -v ollama &>/dev/null; then
    warn "Ollama is installed. Start it with: ollama serve"
  else
    warn "Ollama not installed. Get it at: https://ollama.com"
  fi
fi

# ── 13. Pull image and start containers ───────────────────────────────────────
banner "── Starting OpenClaw ──"

cd "$SCRIPT_DIR"

info "Pulling latest OpenClaw image..."
$DOCKER_CMD pull ghcr.io/openclaw/openclaw:latest

info "Starting containers..."
$COMPOSE_CMD up -d

ok "Containers started."

# ── 14. Done ──────────────────────────────────────────────────────────────────
GATEWAY_TOKEN=$(get_current_token "$OPENCLAW_CONFIG/openclaw.json")

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  OpenClaw is running!${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo ""
echo -e "  URL:    ${BOLD}http://localhost:18789${NC}"
echo -e "  Token:  ${BOLD}${GATEWAY_TOKEN}${NC}"
echo ""

if ! $OLLAMA_OK; then
  echo -e "  ${YELLOW}⚠ Ollama is not running. Start it with: ollama serve${NC}"
  echo ""
fi

if groups "$USER" 2>/dev/null | grep -qv docker && ! docker ps &>/dev/null 2>&1; then
  echo -e "  ${YELLOW}⚠ Log out and back in for Docker to work without sudo.${NC}"
  echo ""
fi

echo "  To stop:   $COMPOSE_CMD down"
echo "  To update: $DOCKER_CMD pull ghcr.io/openclaw/openclaw:latest && $COMPOSE_CMD up -d"
echo ""
