#!/usr/bin/env bash
# OpenClaw Setup Script
# Supports: Ubuntu/Debian (+ derivatives), Arch, Fedora/RHEL, WSL2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_CONFIG="${HOME:-/root}/.openclaw"
OPENCLAW_WORKSPACE="$SCRIPT_DIR/workspace"   # always relative to repo clone

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()   { echo -e "${BLUE}[*]${NC} $1"; }
ok()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
die()    { echo -e "${RED}[✗]${NC} $1"; exit 1; }
banner() { echo -e "\n${BOLD}$1${NC}"; }

# ── Docker / Compose commands (may gain sudo prefix later) ────────────────────
DOCKER_CMD="docker"
COMPOSE_CMD=""

# ── 1. Detect environment ─────────────────────────────────────────────────────
banner "=== OpenClaw Setup ==="
echo ""

IS_WSL=false
if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
  IS_WSL=true
  info "WSL2 environment detected"
fi

# Source distro info
DISTRO="unknown"
DISTRO_LIKE=""
VERSION_CODENAME=""
UBUNTU_CODENAME=""
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO="${ID:-unknown}"
  DISTRO_LIKE="${ID_LIKE:-}"
  VERSION_CODENAME="${VERSION_CODENAME:-}"
  UBUNTU_CODENAME="${UBUNTU_CODENAME:-}"
fi

# Detect effective package manager
PKG_MGR="unknown"
if   command -v apt-get &>/dev/null; then PKG_MGR="apt"
elif command -v pacman  &>/dev/null; then PKG_MGR="pacman"
elif command -v dnf     &>/dev/null; then PKG_MGR="dnf"
elif command -v yum     &>/dev/null; then PKG_MGR="yum"
fi

info "Distro: $DISTRO | PKG: $PKG_MGR | WSL: $IS_WSL"

# ── Helper: resolve sudo or direct root ──────────────────────────────────────
# Some minimal systems don't have sudo (e.g. running as root already)
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo &>/dev/null; then
    SUDO="sudo"
  else
    die "This script requires root or sudo. Please run as root or install sudo."
  fi
fi

# ── Helper: systemd usable? (handles 'degraded' state common on VPS/WSL) ─────
has_systemd() {
  command -v systemctl &>/dev/null || return 1
  # is-system-running returns 1 for "degraded" but systemd IS working
  local state
  state=$(systemctl is-system-running 2>/dev/null || true)
  case "$state" in
    running|degraded) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Helper: Docker apt codename (handles Ubuntu derivatives like Mint, Pop) ───
# Derivatives have their own codename but need Ubuntu's for Docker repo
get_docker_apt_info() {
  # Determine upstream distro for Docker repo
  local docker_distro="$DISTRO"
  local codename=""

  case "$DISTRO" in
    linuxmint|pop|elementary|zorin|lmde|kali)
      # These are Debian/Ubuntu derivatives — use parent
      if echo "$DISTRO_LIKE" in *ubuntu*; then
        docker_distro="ubuntu"
      else
        docker_distro="debian"
      fi
      ;;
    raspbian) docker_distro="debian" ;;
  esac

  # Get codename: UBUNTU_CODENAME (set on derivatives) > VERSION_CODENAME > lsb_release
  if [ -n "$UBUNTU_CODENAME" ]; then
    codename="$UBUNTU_CODENAME"
  elif [ -n "$VERSION_CODENAME" ]; then
    codename="$VERSION_CODENAME"
  elif command -v lsb_release &>/dev/null; then
    codename=$(lsb_release -cs 2>/dev/null || echo "")
  fi

  # Final fallback: try to guess from DISTRO
  if [ -z "$codename" ]; then
    case "$docker_distro" in
      ubuntu) codename="focal" ;;
      debian) codename="bookworm" ;;
      *) die "Could not determine OS codename for Docker repo. Install Docker manually: https://docs.docker.com/engine/install/" ;;
    esac
    warn "Could not detect OS codename, defaulting to '$codename'. If Docker install fails, install manually."
  fi

  echo "$docker_distro $codename"
}

# ── 2. Check internet connectivity ───────────────────────────────────────────
banner "── Checking internet ──"

if curl -fsS --max-time 5 https://google.com -o /dev/null 2>/dev/null \
   || curl -fsS --max-time 5 https://1.1.1.1 -o /dev/null 2>/dev/null; then
  ok "Internet is reachable"
else
  # curl might not be installed yet — try wget or ping as fallback check
  if command -v wget &>/dev/null && wget -q --spider --timeout=5 https://google.com 2>/dev/null; then
    ok "Internet is reachable (via wget)"
  elif ping -c 1 -W 3 8.8.8.8 &>/dev/null 2>&1; then
    ok "Internet is reachable (via ping)"
  else
    die "No internet connection detected. This script needs internet to download packages."
  fi
fi

# ── 3. Check / Install curl ───────────────────────────────────────────────────
# curl is required by virtually everything below — install it first
banner "── Checking curl ──"

if ! command -v curl &>/dev/null; then
  warn "curl not found. Installing..."
  case "$PKG_MGR" in
    apt)    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq curl ;;
    pacman) $SUDO pacman -Sy --noconfirm curl ;;
    dnf)    $SUDO dnf install -y curl ;;
    yum)    $SUDO yum install -y curl ;;
    *)      die "Cannot auto-install curl. Please install it manually then re-run." ;;
  esac
  ok "curl installed."
else
  ok "curl found: $(curl --version | head -1)"
fi

# ── 4. Check / Install git ────────────────────────────────────────────────────
banner "── Checking git ──"

if ! command -v git &>/dev/null; then
  warn "git not found. Installing..."
  case "$PKG_MGR" in
    apt)    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq git ;;
    pacman) $SUDO pacman -Sy --noconfirm git ;;
    dnf)    $SUDO dnf install -y git ;;
    yum)    $SUDO yum install -y git ;;
    *)      die "Cannot auto-install git. Install it manually then re-run." ;;
  esac
  ok "git installed."
else
  ok "git: $(git --version)"
fi

# ── 5. Check / Install Docker ─────────────────────────────────────────────────
banner "── Checking Docker ──"

if ! command -v docker &>/dev/null; then
  warn "Docker not found. Installing..."

  case "$PKG_MGR" in
    apt)
      $SUDO apt-get update -qq
      $SUDO apt-get install -y -qq ca-certificates gnupg lsb-release

      # Resolve distro + codename (handles Ubuntu derivatives)
      read -r DOCKER_DISTRO DOCKER_CODENAME <<< "$(get_docker_apt_info)"
      info "Using Docker repo for: $DOCKER_DISTRO ($DOCKER_CODENAME)"

      $SUDO install -m 0755 -d /etc/apt/keyrings
      curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" \
        | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/${DOCKER_DISTRO} ${DOCKER_CODENAME} stable" \
        | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

      $SUDO apt-get update -qq
      $SUDO apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
      ;;
    pacman)
      $SUDO pacman -Sy --noconfirm docker docker-compose
      ;;
    dnf)
      $SUDO dnf -y install dnf-plugins-core
      # Handle both dnf and dnf5
      if $SUDO dnf config-manager --help &>/dev/null 2>&1; then
        $SUDO dnf config-manager --add-repo \
          https://download.docker.com/linux/fedora/docker-ce.repo
      else
        $SUDO dnf5 config-manager addrepo \
          --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null \
          || $SUDO curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo \
               -o /etc/yum.repos.d/docker-ce.repo
      fi
      $SUDO dnf -y install docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
      ;;
    yum)
      $SUDO yum install -y yum-utils
      $SUDO yum-config-manager --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo
      $SUDO yum install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
      ;;
    *)
      die "Cannot auto-install Docker: unsupported package manager '$PKG_MGR'.\nInstall manually: https://docs.docker.com/engine/install/"
      ;;
  esac

  # Rehash so new binaries are found immediately
  hash -r 2>/dev/null || true
  ok "Docker installed."
else
  ok "Docker: $(docker --version 2>/dev/null | head -1)"
fi

# ── 6. Check / Install Docker Compose ────────────────────────────────────────
# Note: "docker compose version" does NOT need the daemon running
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
  ok "Docker Compose v2: $(docker compose version --short 2>/dev/null)"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
  warn "Using legacy docker-compose v1 — works but consider upgrading."
else
  warn "Docker Compose not found. Installing..."
  case "$PKG_MGR" in
    apt)     $SUDO apt-get install -y -qq docker-compose-plugin ;;
    pacman)  $SUDO pacman -Sy --noconfirm docker-compose ;;
    dnf|yum) $SUDO "${PKG_MGR}" install -y docker-compose-plugin ;;
    *)
      # Universal fallback: download binary directly from GitHub
      info "Downloading Docker Compose binary..."
      COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
      $SUDO curl -fsSL \
        "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
        -o /usr/local/bin/docker-compose
      $SUDO chmod +x /usr/local/bin/docker-compose
      ;;
  esac
  hash -r 2>/dev/null || true
  # Re-detect after install
  if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
  else
    die "Docker Compose installation failed. Install manually: https://docs.docker.com/compose/install/"
  fi
  ok "Docker Compose installed."
fi

# Guard: ensure COMPOSE_CMD is never empty past this point
[ -n "$COMPOSE_CMD" ] || die "Docker Compose not available. Cannot continue."

# ── 7. Start Docker daemon ────────────────────────────────────────────────────
banner "── Starting Docker daemon ──"

start_docker_daemon() {
  if has_systemd; then
    $SUDO systemctl enable docker --now 2>/dev/null || true
    $SUDO systemctl start docker 2>/dev/null || true
  elif command -v service &>/dev/null; then
    # SysV init (older systems, WSL without systemd)
    $SUDO service docker start 2>/dev/null || true
  else
    # Last resort: start dockerd directly (bare WSL, containers)
    warn "No init system detected. Starting dockerd directly..."
    $SUDO dockerd > /tmp/dockerd.log 2>&1 &
  fi

  # Wait up to 25s for daemon
  local tries=0
  while ! $SUDO docker info &>/dev/null 2>&1; do
    sleep 1
    tries=$((tries + 1))
    if [ "$tries" -ge 25 ]; then
      die "Docker daemon did not start in 25s.\nCheck: /tmp/dockerd.log  or  sudo journalctl -u docker -n 50"
    fi
  done
}

# Use sudo for daemon check to avoid false negative when user not in docker group yet
if ! $SUDO docker info &>/dev/null 2>&1; then
  warn "Docker daemon not running. Starting..."
  start_docker_daemon
  ok "Docker daemon started."
else
  ok "Docker daemon is running."
fi

# ── 8. Fix Docker group permissions ──────────────────────────────────────────
if ! docker ps &>/dev/null 2>&1; then
  warn "User '$USER' lacks Docker socket access. Adding to docker group..."
  $SUDO usermod -aG docker "$USER"
  warn "Group change takes effect in a new login session. Using sudo docker for now."
  DOCKER_CMD="sudo docker"
  COMPOSE_CMD="sudo $COMPOSE_CMD"
else
  ok "Docker socket access OK."
fi

# ── 9. Detect token tools: python3 > jq > openssl > urandom ─────────────────
banner "── Checking dependencies ──"

HAS_PYTHON3=false; HAS_JQ=false
command -v python3 &>/dev/null && HAS_PYTHON3=true && ok "python3 found"
command -v jq      &>/dev/null && HAS_JQ=true      && ok "jq found"

generate_token() {
  if $HAS_PYTHON3; then
    python3 -c "import secrets; print(secrets.token_hex(24))"
  elif command -v openssl &>/dev/null; then
    openssl rand -hex 24
  else
    # BUG FIX: wrap in subshell with pipefail OFF to avoid SIGPIPE from head -c
    # killing the script (tr gets 141 when head exits after reading enough bytes)
    ( set +o pipefail; tr -dc 'a-f0-9' < /dev/urandom | head -c 48 )
    echo ""
  fi
}

get_current_token() {
  local file="$1"
  if $HAS_PYTHON3; then
    python3 -c "import json; d=json.load(open('$file')); print(d.get('gateway',{}).get('auth',{}).get('token',''))"
  elif $HAS_JQ; then
    jq -r '.gateway.auth.token // ""' "$file"
  else
    grep -o '"token": *"[^"]*"' "$file" | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
  fi
}

set_token_in_json() {
  local file="$1" token="$2"
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
    local tmp; tmp=$(mktemp)
    jq --arg tok "$token" '.gateway.auth.token = $tok' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    # sed fallback — only works on the known placeholder string
    sed -i "s/CHANGE_ME_USE_SETUP_SH_TO_AUTO_GENERATE/$token/g" "$file"
  fi
}

# ── 10. Check port availability ───────────────────────────────────────────────
banner "── Checking ports ──"

check_port() {
  local port="$1"
  if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | grep -q ":${port}[[:space:]]" && return 0 || return 1
  elif command -v netstat &>/dev/null; then
    netstat -tlnp 2>/dev/null | grep -q ":${port}[[:space:]]" && return 0 || return 1
  fi
  return 1
}

for port in 18789 18790; do
  if check_port "$port"; then
    warn "Port $port is already in use — OpenClaw may fail to bind. Check: ss -tlnp | grep $port"
  else
    ok "Port $port is free."
  fi
done

# ── 11. Create ~/.openclaw config ─────────────────────────────────────────────
banner "── Setting up config ──"

mkdir -p "$OPENCLAW_CONFIG"

if [ ! -f "$OPENCLAW_CONFIG/openclaw.json" ]; then
  cp "$SCRIPT_DIR/config/openclaw.json" "$OPENCLAW_CONFIG/openclaw.json"
  ok "Copied openclaw.json → $OPENCLAW_CONFIG/openclaw.json"
else
  warn "Config already exists — skipping copy. Delete $OPENCLAW_CONFIG/openclaw.json to reset."
fi

# ── 12. Generate gateway auth token ──────────────────────────────────────────
CURRENT_TOKEN=$(get_current_token "$OPENCLAW_CONFIG/openclaw.json")

if [ "$CURRENT_TOKEN" = "CHANGE_ME_USE_SETUP_SH_TO_AUTO_GENERATE" ] || [ -z "$CURRENT_TOKEN" ]; then
  NEW_TOKEN=$(generate_token)
  set_token_in_json "$OPENCLAW_CONFIG/openclaw.json" "$NEW_TOKEN"
  ok "Gateway token generated: ${BOLD}$NEW_TOKEN${NC}"
  echo "    → Save this. You need it to log in."
else
  ok "Gateway token already set."
fi

# ── 13. Set up workspace ──────────────────────────────────────────────────────
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

# ── 14. Write .env with absolute paths ───────────────────────────────────────
# CRITICAL: Docker Compose does NOT expand '~' in .env volume mount values.
# Always write real $HOME-expanded absolute paths.
banner "── Writing .env ──"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  cat > "$SCRIPT_DIR/.env" <<EOF
OPENCLAW_CONFIG_DIR=${OPENCLAW_CONFIG}
OPENCLAW_WORKSPACE_DIR=${OPENCLAW_WORKSPACE}
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_BRIDGE_PORT=18790
OPENCLAW_GATEWAY_BIND=lan
EOF
  ok "Created .env with absolute paths."
else
  # Fix if someone hand-edited .env and put ~ back in
  if grep -q "~/" "$SCRIPT_DIR/.env" 2>/dev/null; then
    warn ".env has '~/' — fixing to absolute paths..."
    sed -i "s|~/.openclaw|${OPENCLAW_CONFIG}|g"           "$SCRIPT_DIR/.env"
    sed -i "s|~/openclaw/workspace|${OPENCLAW_WORKSPACE}|g" "$SCRIPT_DIR/.env"
    ok ".env paths fixed."
  else
    ok ".env already exists with correct paths."
  fi
fi

# ── 15. Check / Install / Start Ollama ───────────────────────────────────────
banner "── Checking Ollama ──"

OLLAMA_OK=false

ollama_is_running() {
  curl -sf --max-time 3 http://localhost:11434 &>/dev/null \
    || curl -sf --max-time 3 http://127.0.0.1:11434 &>/dev/null
}

if ollama_is_running; then
  OLLAMA_OK=true
  ok "Ollama is already running on port 11434."
else
  # Install if binary not found
  if ! command -v ollama &>/dev/null; then
    info "Ollama not found. Installing via official installer..."
    if curl -fsSL --max-time 60 https://ollama.com/install.sh | sh; then
      hash -r 2>/dev/null || true
      ok "Ollama installed."
    else
      warn "Ollama installation failed. You can install it manually: https://ollama.com"
      warn "Models will not work until Ollama is running."
    fi
  else
    ok "Ollama binary: $(command -v ollama)"
  fi

  # Start Ollama if binary is now available
  if command -v ollama &>/dev/null; then
    info "Starting Ollama..."
    if has_systemd && $SUDO systemctl list-unit-files ollama.service &>/dev/null 2>&1; then
      $SUDO systemctl enable ollama --now 2>/dev/null || true
      $SUDO systemctl start ollama 2>/dev/null || true
    else
      # WSL or no systemd: start in background
      # Use nohup if available, plain & otherwise
      if command -v nohup &>/dev/null; then
        nohup ollama serve > /tmp/ollama.log 2>&1 &
      else
        ollama serve > /tmp/ollama.log 2>&1 &
      fi
      info "Ollama started in background. Log: /tmp/ollama.log"
    fi

    # Wait up to 15s
    info "Waiting for Ollama..."
    tries=0
    while ! ollama_is_running; do
      sleep 1
      tries=$((tries + 1))
      [ "$tries" -ge 15 ] && break
    done

    if ollama_is_running; then
      OLLAMA_OK=true
      ok "Ollama is running."
    else
      warn "Ollama didn't respond in 15s. It may still be starting."
      warn "If models fail, run manually: ollama serve"
    fi
  fi
fi

# ── 16. Pull image and start containers ──────────────────────────────────────
banner "── Starting OpenClaw containers ──"

cd "$SCRIPT_DIR"

info "Pulling latest OpenClaw image (this may take a minute)..."
if ! $DOCKER_CMD pull ghcr.io/openclaw/openclaw:latest; then
  warn "Image pull failed. Trying to start with cached image if available..."
fi

info "Starting containers..."
if ! $COMPOSE_CMD up -d; then
  echo ""
  die "Failed to start containers. Common causes:
  - Port 18789 or 18790 is in use (check: ss -tlnp)
  - .env paths are wrong (check: cat $SCRIPT_DIR/.env)
  - Docker daemon issue (check: $DOCKER_CMD ps)
  Run '$COMPOSE_CMD logs' for details."
fi

ok "Containers started."

# ── 17. Generate info.sh (run anytime to see URL + token) ────────────────────
cat > "$SCRIPT_DIR/info.sh" <<'INFOSH'
#!/usr/bin/env bash
CONFIG_FILE="${HOME:-/root}/.openclaw/openclaw.json"
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

[ -f "$CONFIG_FILE" ] || { echo "Config not found. Run ./setup.sh first."; exit 1; }

# Extract token — three methods in order of reliability.
# OpenClaw sometimes writes non-standard JSON (comments, trailing commas)
# so we avoid full JSON parsing and use grep as the primary method.
TOKEN=""

# Method 1: grep — works even if JSON is malformed
TOKEN=$(grep -o '"token": *"[^"]*"' "$CONFIG_FILE" 2>/dev/null \
  | head -1 | sed 's/.*"token": *"\([^"]*\)"/\1/')

# Method 2: jq — if grep got nothing and jq is available
if [ -z "$TOKEN" ] && command -v jq &>/dev/null; then
  TOKEN=$(jq -r '.gateway.auth.token // ""' "$CONFIG_FILE" 2>/dev/null || true)
fi

# Method 3: python3 with error handling — last resort
if [ -z "$TOKEN" ] && command -v python3 &>/dev/null; then
  TOKEN=$(python3 -c "
import json, re, sys
try:
    d = json.load(open('$CONFIG_FILE'))
    print(d['gateway']['auth']['token'])
except Exception:
    # Try stripping comments then parsing
    try:
        raw = open('$CONFIG_FILE').read()
        raw = re.sub(r'//.*', '', raw)
        raw = re.sub(r',\s*([}\]])', r'\1', raw)
        d = json.loads(raw)
        print(d['gateway']['auth']['token'])
    except Exception:
        pass
" 2>/dev/null || true)
fi

if [ -z "$TOKEN" ]; then
  echo "Could not read token from $CONFIG_FILE"
  echo "Open the file and look for: \"token\": \"...\""
  exit 1
fi

# Detect WSL and get IP
IS_WSL=false; WSL_IP=""
grep -qiE "microsoft|wsl" /proc/version 2>/dev/null && IS_WSL=true
$IS_WSL && WSL_IP=$(hostname -I 2>/dev/null | awk '{print $1}') || true

# Build full clickable URLs with token embedded
LOCAL_URL="http://localhost:18789/?token=${TOKEN}"
WSL_URL="http://${WSL_IP}:18789/?token=${TOKEN}"

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  OpenClaw Dashboard${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo ""
echo -e "  Token:  ${BOLD}${TOKEN}${NC}"
echo ""
if $IS_WSL && [ -n "$WSL_IP" ]; then
  echo -e "  ${YELLOW}Running in WSL — open one of these in Windows Chrome:${NC}"
  echo ""
  echo -e "  Try first:  ${BOLD}${LOCAL_URL}${NC}"
  echo -e "  Fallback:   ${BOLD}${WSL_URL}${NC}"
else
  echo -e "  Open in browser:  ${BOLD}${LOCAL_URL}${NC}"
fi
echo ""
echo "  The token is already embedded in the URL — just click and you're in."
echo ""
INFOSH

chmod +x "$SCRIPT_DIR/info.sh"
ok "Created info.sh — run ./info.sh anytime to see your URL and token."

# ── 18. Final output ──────────────────────────────────────────────────────────
# Use grep for token extraction — avoids JSON parse errors from OpenClaw's config format
GATEWAY_TOKEN=$(grep -o '"token": *"[^"]*"' "$OPENCLAW_CONFIG/openclaw.json" 2>/dev/null \
  | head -1 | sed 's/.*"token": *"\([^"]*\)"/\1/' || true)
[ -z "$GATEWAY_TOKEN" ] && GATEWAY_TOKEN=$(get_current_token "$OPENCLAW_CONFIG/openclaw.json")

WSL_IP=""
$IS_WSL && WSL_IP=$(hostname -I 2>/dev/null | awk '{print $1}') || true

LOCAL_URL="http://localhost:18789/?token=${GATEWAY_TOKEN}"

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  OpenClaw is running!${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo ""
echo -e "  Token:  ${BOLD}${GATEWAY_TOKEN}${NC}"
echo ""

if $IS_WSL && [ -n "$WSL_IP" ]; then
  echo -e "  ${YELLOW}Running in WSL — open one of these in Windows Chrome:${NC}"
  echo ""
  echo -e "  Try first:  ${BOLD}http://localhost:18789/?token=${GATEWAY_TOKEN}${NC}"
  echo -e "  Fallback:   ${BOLD}http://${WSL_IP}:18789/?token=${GATEWAY_TOKEN}${NC}"
  echo ""
else
  echo -e "  Open in browser:  ${BOLD}${LOCAL_URL}${NC}"
  echo ""
fi

if ! $OLLAMA_OK; then
  echo -e "  ${YELLOW}⚠  Ollama may still be starting up.${NC}"
  echo -e "  ${YELLOW}   If models don't respond, run: ollama serve${NC}"
  echo ""
fi

# Use $DOCKER_CMD here (not bare 'docker') to avoid false warning
if ! $DOCKER_CMD ps &>/dev/null 2>&1; then
  echo -e "  ${YELLOW}⚠  Log out and back in for Docker to work without sudo.${NC}"
  echo ""
fi

echo "  Show this again:  ./info.sh"
echo "  Stop:             $COMPOSE_CMD down"
echo "  Update:           $DOCKER_CMD pull ghcr.io/openclaw/openclaw:latest && $COMPOSE_CMD up -d"
echo ""
