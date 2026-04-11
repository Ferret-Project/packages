#!/usr/bin/env bash
# ================================================================
#  Neovim-Setup — Installs Neovim and optional preconfigured setups
#  AstroNvim / LazyVim / Default
#  Made for Zodium Project
# ================================================================
# @tags: Applications

set -Eeuo pipefail

# ── Dependency check ──────────────────────────────────────────
# brew is only required if nvim needs to be installed — checked later
command -v git &>/dev/null || { printf '%s\n' "⦻  git is required but not installed" >&2; exit 1; }

# ── Styling ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'
DIM='\033[2m'; BLUE='\033[0;34m'

say()  { printf '%b\n' "$*"; }
info() { say "${CYAN}◈${NC}  $*"; }
ok()   { say "${GREEN}◆${NC}  $*"; }
warn() { say "${YELLOW}◇${NC}  $*"; }
fail() { say "${RED}⦻${NC}  $*" >&2; exit 1; }
step() { say "${BLUE}›${NC}  $*"; }

# ── Paths ─────────────────────────────────────────────────────
NVIM_CONFIG="$HOME/.config/nvim"
NVIM_DIRS=(
    "$HOME/.config/nvim"
    "$HOME/.local/share/nvim"
    "$HOME/.local/state/nvim"
    "$HOME/.cache/nvim"
)
MARKER_FILE="$NVIM_CONFIG/.zodium-setup"
BACKUP_BASE="$HOME/.local/share/zodium/backups"

# ── Flags ─────────────────────────────────────────────────────
SETUP=""          # astronvim | lazyvim | default
ASSUME_YES=false
BACKUP=false
FORCE=false

usage() {
    say "Usage: ${0##*/} [options] [setup]"
    say ""
    say "Setups:"
    say "  ${CYAN}astronvim${NC}    batteries-included IDE experience"
    say "  ${CYAN}lazyvim${NC}      modern, lazy-loaded plugin framework"
    say "  ${CYAN}default${NC}      clean slate, no plugins"
    say ""
    say "Options:"
    say "  ${CYAN}--backup${NC}     back up existing config + caches before replacing"
    say "  ${CYAN}--force${NC}      wipe existing Neovim config + caches without prompting"
    say "  ${CYAN}--yes${NC}        skip all confirmation prompts"
    say "  ${CYAN}--help${NC}       show this message"
    say ""
    say "Examples:"
    say "  ${DIM}${0##*/} lazyvim --backup${NC}"
    say "  ${DIM}${0##*/} astronvim --yes${NC}"
    say "  ${DIM}${0##*/} astronvim --backup --force${NC}"
    say ""
    say "${YELLOW}◇${NC}  This script will remove existing Neovim config if a setup is applied."
    say "  Use ${BOLD}--backup${NC} to save a timestamped copy first."
    say ""
    exit 0
}

while (( $# > 0 )); do
    case "$1" in
        astronvim|lazyvim|default) SETUP="$1" ;;
        --backup)  BACKUP=true ;;
        --force)   FORCE=true ;;
        --yes)     ASSUME_YES=true ;;
        --help|-h) usage ;;
        *) fail "Unknown option: $1  (try --help)" ;;
    esac
    shift
done

# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔═════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  Zodium Neovim Setup  ◈     ║${NC}"
say "${MAGENTA}${BOLD}╚═════════════════════════════════╝${NC}"
say ""

# ── Helpers ───────────────────────────────────────────────────
confirm() {
    local prompt=${1:-"Continue?"}
    $ASSUME_YES && return 0
    printf '%b [y/N]: ' "$prompt"
    read -r _ans
    [[ "$_ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

menu() {
    local i=1 max=$#
    for opt in "$@"; do
        say "  ${DIM}$i)${NC}  ${CYAN}$opt${NC}"
        (( i++ ))
    done
    while :; do
        printf '\n  ' && printf '%b' "${DIM}choose:${NC} "
        read -r PICK
        say ""
        [[ "$PICK" =~ ^[1-9][0-9]*$ ]] && (( PICK >= 1 && PICK <= max )) && break
        warn "Invalid choice — enter a number between 1 and $max"
    done
}

# ── Scan ──────────────────────────────────────────────────────
NVIM_INSTALLED=false
command -v nvim &>/dev/null && NVIM_INSTALLED=true

EXISTING_SETUP=""
[[ -f "$MARKER_FILE" ]] && EXISTING_SETUP=$(< "$MARKER_FILE")

HAS_EXISTING=false
for d in "${NVIM_DIRS[@]}"; do
    if [[ -e "$d" ]]; then
        HAS_EXISTING=true
        break
    fi
done

# ── Status ────────────────────────────────────────────────────
if $NVIM_INSTALLED; then
    ok "Neovim installed  ${DIM}$(nvim --version | head -1)${NC}"
else
    warn "Neovim not installed"
fi
if $HAS_EXISTING; then
    if [[ -n "$EXISTING_SETUP" ]]; then
        warn "Existing Neovim data detected  ${DIM}($EXISTING_SETUP)${NC}"
    else
        warn "Existing Neovim data detected  ${DIM}(unmanaged)${NC}"
    fi
fi
say ""

# ── Install Neovim if needed ──────────────────────────────────
if ! $NVIM_INSTALLED; then
    if [[ -z "$SETUP" ]]; then
        PICK=""
        menu "Install Neovim + pick setup" "Exit"
        [[ "$PICK" != "1" ]] && { info "Bye!"; exit 0; }
    fi
    command -v brew &>/dev/null || fail "Homebrew is required to install Neovim (brew not found)"
    step "Installing Neovim via Homebrew..."
    brew install neovim || fail "Neovim installation failed"
    ok "Neovim installed  ${DIM}$(nvim --version | head -1)${NC}"
    say ""
fi

# ── Pick setup interactively if not set via flag ──────────────
if [[ -z "$SETUP" ]]; then
    $HAS_EXISTING && warn "Choosing a setup will replace your existing config"

    ASTRONVIM_LABEL="AstroNvim  ${DIM}— batteries-included${NC}"
    LAZYVIM_LABEL="LazyVim    ${DIM}— modern, lazy-loaded${NC}"
    DEFAULT_LABEL="Default    ${DIM}— clean slate${NC}"
    [[ "$EXISTING_SETUP" == "astronvim" ]] && ASTRONVIM_LABEL+="  ${GREEN}(active)${NC}"
    [[ "$EXISTING_SETUP" == "lazyvim"   ]] && LAZYVIM_LABEL+="  ${GREEN}(active)${NC}"
    [[ "$EXISTING_SETUP" == "default"   ]] && DEFAULT_LABEL+="  ${GREEN}(active)${NC}"

    PICK=""
    menu "$ASTRONVIM_LABEL" "$LAZYVIM_LABEL" "$DEFAULT_LABEL" "Exit"
    case "$PICK" in
        1) SETUP="astronvim" ;;
        2) SETUP="lazyvim" ;;
        3) SETUP="default" ;;
        *) info "Bye!"; exit 0 ;;
    esac
fi

[[ -n "$SETUP" ]] || fail "No setup selected"

# ── Handle existing config ────────────────────────────────────
if $HAS_EXISTING; then
    if $BACKUP; then
        BACKUP_DIR="$BACKUP_BASE/nvim-$(date +%Y-%m-%d_%H-%M-%S)"
        confirm "${YELLOW}Back up existing config + caches to ${BOLD}${BACKUP_DIR}${NC}${YELLOW}?${NC}" \
            || { info "Cancelled"; exit 0; }
        step "Backing up to $BACKUP_DIR..."
        mkdir -p "$BACKUP_DIR"
        for d in "${NVIM_DIRS[@]}"; do
            [[ -d "$d" ]] && cp -a "$d" "$BACKUP_DIR/"
        done
        ok "Backup saved  ${DIM}($BACKUP_DIR)${NC}"
        say ""
    fi

    if ! $FORCE && ! $BACKUP; then
        warn "This will permanently remove your existing Neovim config and caches."
        confirm "${RED}Continue and wipe existing config?${NC}" || { info "Cancelled"; exit 0; }
    elif ! $FORCE && $BACKUP; then
        : # backup already confirmed above — proceed without second prompt
    fi
fi

# ── Clone to temp first, then wipe and place ─────────────────
wipe_config() {
    local d
    for d in "${NVIM_DIRS[@]}"; do
        if [[ -d "$d" && "$d" == "$HOME/"* ]]; then
            step "Removing $d"
            rm -rf -- "$d"
        fi
    done
}

case "$SETUP" in
    astronvim|lazyvim)
        TMP_DIR="$(mktemp -d)"
        trap 'rm -rf -- "$TMP_DIR"' EXIT

        if [[ "$SETUP" == "astronvim" ]]; then
            info "Cloning AstroNvim template..."
            git clone --depth 1 https://github.com/AstroNvim/template "$TMP_DIR" \
                || fail "Failed to clone AstroNvim (check your internet connection)"
        else
            info "Cloning LazyVim starter..."
            git clone --depth 1 https://github.com/LazyVim/starter "$TMP_DIR" \
                || fail "Failed to clone LazyVim (check your internet connection)"
        fi

        rm -rf "$TMP_DIR/.git"

        # Clone succeeded — safe to wipe now
        $HAS_EXISTING && wipe_config
        mkdir -p "$(dirname "$NVIM_CONFIG")"
        mv "$TMP_DIR" "$NVIM_CONFIG"
        trap - EXIT

        echo "$SETUP" > "$MARKER_FILE"
        ok "$( [[ "$SETUP" == astronvim ]] && printf 'AstroNvim' || printf 'LazyVim' ) installed"
        ;;
    default)
        $HAS_EXISTING && wipe_config
        mkdir -p "$NVIM_CONFIG"
        echo "default" > "$MARKER_FILE"
        ok "Clean slate ready"
        ;;
esac

# ── Optional tool hints ───────────────────────────────────────
if [[ "$SETUP" != "default" ]]; then
    MISSING_TOOLS=()
    for tool in rg fd fzf node; do
        command -v "$tool" &>/dev/null || MISSING_TOOLS+=("$tool")
    done
    if (( ${#MISSING_TOOLS[@]} > 0 )); then
        say ""
        warn "Optional tools not found: ${BOLD}${MISSING_TOOLS[*]}${NC}"
        say "  ${DIM}These improve plugin functionality (LSP, search, pickers)${NC}"
        if command -v brew &>/dev/null; then
            say "  ${DIM}Install with: brew install ${MISSING_TOOLS[*]}${NC}"
        else
            say "  ${DIM}Install them using your system package manager${NC}"
        fi
    fi
fi

# ── Summary ───────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔═══════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◆  Neovim Setup Complete    ║${NC}"
say "${MAGENTA}${BOLD}╚═══════════════════════════════╝${NC}"
say "  Setup : ${BOLD}$SETUP${NC}"
if [[ "$SETUP" == "default" ]]; then
    say "  Run   : ${BOLD}nvim${NC} to get started"
else
    say "  Run   : ${BOLD}nvim${NC} to finish plugin installation"
fi
say "  Tip   : Run ${BOLD}:checkhealth${NC} inside Neovim if something looks off"
say ""