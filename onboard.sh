#!/usr/bin/env bash
# onboard.sh — OpenClaw interactive setup bridge
# Wraps OpenClaw CLI with a friendly command interface.
# All actual UI, QR codes, and prompts are handled by OpenClaw itself.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ── CLI runner ─────────────────────────────────────────────────────────────────
# Detect docker command (sudo or not)
if docker ps &>/dev/null 2>&1; then
  DC="docker compose"
else
  DC="sudo docker compose"
fi

run_cli() {
  # -it ensures TTY allocation so QR codes, spinners, and prompts render correctly
  $DC run --rm -it openclaw-cli "$@"
}

# ── Check OpenClaw gateway is running ─────────────────────────────────────────
check_running() {
  if ! $DC ps --services --filter "status=running" 2>/dev/null | grep -q "openclaw-gateway"; then
    echo -e "\n${RED}[✗]${NC} OpenClaw is not running."
    echo -e "    Start it first: ${BOLD}docker compose up -d${NC}\n"
    exit 1
  fi
}

# ── Arrow-key selection menu ───────────────────────────────────────────────────
# Usage:   arrow_menu "Title" "Option 1" "Option 2" ...
# Returns: $SELECTED = chosen index, or -1 if cancelled
SELECTED=-1
arrow_menu() {
  local title="$1"; shift
  local options=("$@")
  local count=${#options[@]}
  local current=0

  tput civis 2>/dev/null || true   # hide cursor

  echo -e "\n${BOLD}${title}${NC}"
  echo -e "${DIM}  ↑ ↓  navigate    Enter  select    q  cancel${NC}\n"

  _draw() {
    for i in "${!options[@]}"; do
      if [ "$i" -eq "$current" ]; then
        echo -e "  ${CYAN}▶ ${BOLD}${options[$i]}${NC}"
      else
        echo -e "    ${DIM}${options[$i]}${NC}"
      fi
    done
  }

  _draw

  while true; do
    IFS= read -rsn1 key

    if [[ "$key" == $'\x1b' ]]; then
      IFS= read -rsn2 key2 2>/dev/null || true
      case "$key2" in
        '[A') [ "$current" -gt 0 ]             && current=$((current - 1)) ;;
        '[B') [ "$current" -lt $((count - 1)) ] && current=$((current + 1)) ;;
      esac
    elif [[ "$key" == "" ]]; then   # Enter
      break
    elif [[ "$key" == "q" || "$key" == "Q" ]]; then
      tput cnorm 2>/dev/null || true
      echo ""
      SELECTED=-1
      return
    fi

    tput cuu "$count" 2>/dev/null || true
    _draw
  done

  tput cnorm 2>/dev/null || true
  echo ""
  SELECTED=$current
}

# ── Banner ─────────────────────────────────────────────────────────────────────
show_banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════╗"
  echo "  ║        OpenClaw Setup Bridge          ║"
  echo "  ╚═══════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  Type a command below and press ${BOLD}Enter${NC}."
  echo -e "  Type ${BOLD}help${NC} to see all commands.\n"
}

# ── Help ───────────────────────────────────────────────────────────────────────
show_help() {
  echo -e "\n${BOLD}Available commands:${NC}\n"
  echo -e "  ${CYAN}${BOLD}Channels${NC}"
  echo -e "  ${GREEN}connect whatsapp${NC}     Connect your WhatsApp account (shows QR code)"
  echo -e "  ${GREEN}connect telegram${NC}     Connect a Telegram bot"
  echo -e "  ${GREEN}connect discord${NC}      Connect a Discord bot"
  echo -e "  ${GREEN}channel status${NC}       Show all channel connection health\n"

  echo -e "  ${CYAN}${BOLD}Models${NC}"
  echo -e "  ${GREEN}models${NC}               Browse and configure AI model providers\n"

  echo -e "  ${CYAN}${BOLD}Setup${NC}"
  echo -e "  ${GREEN}configure${NC}            Full interactive config (credentials, gateway, agents)"
  echo -e "  ${GREEN}onboard${NC}              Run the OpenClaw onboarding wizard"
  echo -e "  ${GREEN}plugins${NC}              Manage plugins and extensions\n"

  echo -e "  ${CYAN}${BOLD}Info & Tools${NC}"
  echo -e "  ${GREEN}status${NC}               Show running channels and recent sessions"
  echo -e "  ${GREEN}doctor${NC}               Run health checks and quick fixes"
  echo -e "  ${GREEN}tui${NC}                  Open the full terminal UI"
  echo -e "  ${GREEN}dashboard${NC}            Show dashboard URL and login token"
  echo -e "  ${GREEN}logs${NC}                 Tail live gateway logs\n"

  echo -e "  ${CYAN}${BOLD}Other${NC}"
  echo -e "  ${GREEN}help${NC}                 Show this help"
  echo -e "  ${GREEN}clear${NC}                Clear the screen"
  echo -e "  ${GREEN}exit${NC}                 Exit this bridge\n"
}

# ── Command: connect ───────────────────────────────────────────────────────────
cmd_connect() {
  local channel="${1:-}"

  if [ -z "$channel" ]; then
    arrow_menu "Which channel do you want to connect?" \
      "WhatsApp" \
      "Telegram" \
      "Discord" \
      "Cancel"

    case "$SELECTED" in
      0) channel="whatsapp" ;;
      1) channel="telegram" ;;
      2) channel="discord"  ;;
      *) echo -e "${DIM}Cancelled.${NC}\n"; return ;;
    esac
  fi

  case "$channel" in
    whatsapp)
      echo -e "\n${BLUE}[*]${NC} Starting WhatsApp connection — scan the QR code with your phone.\n"
      run_cli channels login --verbose
      ;;
    telegram)
      echo -e "\n${BLUE}[*]${NC} Starting Telegram connection.\n"
      run_cli channels login --channel telegram --verbose
      ;;
    discord)
      echo -e "\n${BLUE}[*]${NC} Starting Discord connection.\n"
      run_cli channels login --channel discord --verbose
      ;;
    *)
      echo -e "${RED}Unknown channel:${NC} $channel. Try: whatsapp, telegram, discord\n"
      ;;
  esac
}

# ── Command: models ────────────────────────────────────────────────────────────
cmd_models() {
  arrow_menu "What do you want to do?" \
    "Configure a model provider (add API key / credentials)" \
    "List configured models" \
    "Scan for available models" \
    "Cancel"

  case "$SELECTED" in
    0)
      # Provider selection with arrow keys — OpenClaw configure handles the rest
      arrow_menu "Select a provider to configure:" \
        "Ollama  (local + cloud models — already set up)" \
        "OpenAI  (GPT-4, GPT-4o, etc.)" \
        "Anthropic  (Claude models)" \
        "Google  (Gemini models)" \
        "Mistral" \
        "Groq" \
        "Azure OpenAI" \
        "Other / Custom" \
        "Cancel"

      if [ "$SELECTED" -eq -1 ] || [ "$SELECTED" -eq 8 ]; then
        echo -e "${DIM}Cancelled.${NC}\n"; return
      fi

      echo -e "\n${BLUE}[*]${NC} Launching OpenClaw model configuration...\n"
      # Pass to OpenClaw's own interactive configure — it handles API keys, OAuth, etc.
      run_cli configure
      ;;
    1)
      echo -e "\n${BLUE}[*]${NC} Listing configured models...\n"
      run_cli models list 2>/dev/null || run_cli models
      ;;
    2)
      echo -e "\n${BLUE}[*]${NC} Scanning for available models...\n"
      run_cli models scan 2>/dev/null || run_cli models
      ;;
    *)
      echo -e "${DIM}Cancelled.${NC}\n"
      ;;
  esac
}

# ── Command: channel status ────────────────────────────────────────────────────
cmd_channel_status() {
  echo -e "\n${BLUE}[*]${NC} Fetching channel status...\n"
  run_cli status
}

# ── Command: dashboard ─────────────────────────────────────────────────────────
cmd_dashboard() {
  if [ -f "$SCRIPT_DIR/info.sh" ]; then
    bash "$SCRIPT_DIR/info.sh"
  else
    echo -e "\n${YELLOW}[!]${NC} info.sh not found. Run ./setup.sh first.\n"
  fi
}

# ── Main prompt loop ───────────────────────────────────────────────────────────
check_running
show_banner
show_help

while true; do
  echo -ne "${CYAN}${BOLD}openclaw${NC}${BOLD}>${NC} "
  IFS= read -r input || { echo ""; break; }

  # Normalize: lowercase, trim whitespace
  cmd=$(echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  case "$cmd" in
    # ── Channel commands ──────────────────────────────────────────────────────
    "connect whatsapp" | "whatsapp")
      cmd_connect "whatsapp" ;;
    "connect telegram" | "telegram")
      cmd_connect "telegram" ;;
    "connect discord"  | "discord")
      cmd_connect "discord" ;;
    "connect")
      cmd_connect "" ;;
    "channel status" | "channels")
      cmd_channel_status ;;

    # ── Model commands ────────────────────────────────────────────────────────
    "models" | "model" | "change model" | "add model" | "configure model")
      cmd_models ;;

    # ── Setup commands ────────────────────────────────────────────────────────
    "configure" | "config")
      echo -e "\n${BLUE}[*]${NC} Launching interactive configuration...\n"
      run_cli configure ;;
    "onboard")
      echo -e "\n${BLUE}[*]${NC} Launching onboarding wizard...\n"
      run_cli onboard ;;
    "plugins" | "plugin")
      echo -e "\n${BLUE}[*]${NC} Opening plugin manager...\n"
      run_cli plugins ;;

    # ── Info & tools ──────────────────────────────────────────────────────────
    "status")
      echo -e "\n${BLUE}[*]${NC} Fetching status...\n"
      run_cli status ;;
    "doctor")
      echo -e "\n${BLUE}[*]${NC} Running health checks...\n"
      run_cli doctor ;;
    "tui")
      echo -e "\n${BLUE}[*]${NC} Opening terminal UI...\n"
      run_cli tui ;;
    "logs" | "log")
      echo -e "\n${BLUE}[*]${NC} Tailing logs (Ctrl+C to stop)...\n"
      run_cli logs ;;
    "dashboard" | "token" | "url")
      cmd_dashboard ;;

    # ── Meta ──────────────────────────────────────────────────────────────────
    "help" | "?" | "h")
      show_help ;;
    "clear" | "cls")
      show_banner ;;
    "exit" | "quit" | "q" | "bye")
      echo -e "\n${DIM}Goodbye.${NC}\n"
      exit 0 ;;
    "")
      ;;   # ignore empty input
    *)
      echo -e "\n${YELLOW}Unknown command:${NC} '$cmd'  — type ${BOLD}help${NC} to see available commands.\n" ;;
  esac
done
