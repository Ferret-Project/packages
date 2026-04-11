#!/usr/bin/env bash
# ================================================================
#  Razer Setup — Polychromatic + OpenRazer Daemon Manager
# ================================================================
# @tags: Hardware

set -Eeuo pipefail

command -v flatpak   &>/dev/null || { printf '%s\n' "⦻  flatpak is required"  >&2; exit 1; }
command -v systemctl &>/dev/null || { printf '%s\n' "⦻  systemctl is required" >&2; exit 1; }

# ── Styling ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'
DIM='\033[2m'; BLUE='\033[0;34m'

say()  { printf '%b\n' "$*"; }
ok()   { say "${GREEN}◆${NC}  $*"; }
warn() { say "${YELLOW}◇${NC}  $*"; }
fail() { say "${RED}⦻${NC}  $*" >&2; exit 1; }
step() { say "${BLUE}›${NC}  $*"; }

# ── Config ────────────────────────────────────────────────────
POLY_NAME="Polychromatic"
POLY_ID="app.polychromatic.controller"
DAEMON_SERVICE="openrazer-daemon.service"

# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔══════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  Razer Setup  ◈          ║${NC}"
say "${MAGENTA}${BOLD}╚══════════════════════════════╝${NC}"
say ""

# ── Flathub ───────────────────────────────────────────────────
# Check both scopes — Flathub may be registered system-wide
has_flathub() {
    flatpak --user   remote-list --columns=name 2>/dev/null | grep -qx 'flathub' && return 0
    flatpak --system remote-list --columns=name 2>/dev/null | grep -qx 'flathub' && return 0
    return 1
}

ensure_flathub() {
    has_flathub && return
    step "Adding Flathub (--user)..."
    if flatpak --user remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo; then
        ok "Flathub added"
    else
        fail "Failed to add Flathub"
    fi
}

# ── State detection ───────────────────────────────────────────
poly_installed() {
    flatpak --user   info "$POLY_ID" &>/dev/null && return 0
    flatpak --system info "$POLY_ID" &>/dev/null && return 0
    return 1
}

daemon_enabled() {
    systemctl --user is-enabled "$DAEMON_SERVICE" &>/dev/null
}

daemon_active() {
    systemctl --user is-active "$DAEMON_SERVICE" &>/dev/null
}

detect_state() {
    POLY_INSTALLED=false
    DAEMON_ENABLED=false
    DAEMON_ACTIVE=false

    poly_installed && POLY_INSTALLED=true
    daemon_enabled && DAEMON_ENABLED=true
    daemon_active  && DAEMON_ACTIVE=true

    if $POLY_INSTALLED && $DAEMON_ENABLED; then
        INSTALL_STATE="full"
    elif $POLY_INSTALLED || $DAEMON_ENABLED; then
        INSTALL_STATE="partial"
    else
        INSTALL_STATE="none"
    fi
}

detect_state

# ── Status display ────────────────────────────────────────────
case "$INSTALL_STATE" in
    none)    warn "Nothing installed" ;;
    full)    ok   "Fully set up" ;;
    partial) warn "Partial setup detected" ;;
esac

has_flathub \
    && say "  ${GREEN}◆${NC}  ${DIM}Flathub${NC}" \
    || say "  ${RED}✗${NC}  ${DIM}Flathub${NC}"

$POLY_INSTALLED \
    && say "  ${GREEN}◆${NC}  ${DIM}$POLY_NAME (Flatpak)${NC}" \
    || say "  ${RED}✗${NC}  ${DIM}$POLY_NAME (Flatpak)${NC}"

if $DAEMON_ENABLED; then
    $DAEMON_ACTIVE \
        && say "  ${GREEN}◆${NC}  ${DIM}$DAEMON_SERVICE (enabled, running)${NC}" \
        || say "  ${YELLOW}◇${NC}  ${DIM}$DAEMON_SERVICE (enabled, stopped)${NC}"
else
    say "  ${RED}✗${NC}  ${DIM}$DAEMON_SERVICE (disabled)${NC}"
fi
say ""

# ── Helpers ───────────────────────────────────────────────────
confirm() {
    printf '%b [y/N]: ' "$1"
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
        printf '\n  %b' "${DIM}choose:${NC} "
        read -r PICK
        say ""
        [[ "$PICK" =~ ^[1-9][0-9]*$ ]] && (( PICK >= 1 && PICK <= max )) && break
        warn "Invalid choice — enter a number between 1 and $max"
    done
}

# ── Core ops ──────────────────────────────────────────────────
_install_flatpak() {
    ensure_flathub
    if ! $POLY_INSTALLED; then
        # Install into whichever scope has the flathub remote
        local scope="--user"
        flatpak --system remote-list --columns=name 2>/dev/null | grep -qx 'flathub' && scope="--system"
        step "Installing $POLY_NAME ($scope)..."
        flatpak install -y "$scope" flathub "$POLY_ID" \
            && ok "$POLY_NAME installed" \
            || warn "$POLY_NAME install failed"
    else
        ok "$POLY_NAME already installed"
    fi
}

_enable_daemon() {
    if ! $DAEMON_ENABLED; then
        step "Enabling $DAEMON_SERVICE..."
        systemctl --user enable --now "$DAEMON_SERVICE" \
            && ok "Daemon enabled and started" \
            || warn "Failed to enable daemon — is openrazer installed on the host?"
    else
        ok "Daemon already enabled"
        if ! $DAEMON_ACTIVE; then
            step "Starting daemon..."
            systemctl --user start "$DAEMON_SERVICE" \
                && ok "Daemon started" \
                || warn "Failed to start daemon"
        fi
    fi
}

_disable_daemon() {
    if $DAEMON_ENABLED; then
        step "Disabling $DAEMON_SERVICE..."
        systemctl --user disable --now "$DAEMON_SERVICE" 2>/dev/null \
            && ok "Daemon stopped and disabled" \
            || warn "Could not disable daemon"
    else
        ok "Daemon already disabled"
    fi
}

_remove_flatpak() {
    if $POLY_INSTALLED; then
        step "Removing $POLY_NAME..."
        local removed=false
        flatpak --user   info "$POLY_ID" &>/dev/null             && flatpak uninstall -y --user   "$POLY_ID" >/dev/null && removed=true || true
        flatpak --system info "$POLY_ID" &>/dev/null             && flatpak uninstall -y --system "$POLY_ID" >/dev/null && removed=true || true
        $removed             && ok "$POLY_NAME removed"             || warn "Removal failed"
    else
        ok "$POLY_NAME not installed, skipping"
    fi
}

# ── Actions ───────────────────────────────────────────────────

do_setup() {
    _install_flatpak
    _enable_daemon
}

do_reinstall() {
    confirm "${YELLOW}Reinstall Polychromatic + restart daemon?${NC}" \
        || { ok "Cancelled"; exit 0; }
    _disable_daemon
    _remove_flatpak
    POLY_INSTALLED=false
    DAEMON_ENABLED=false
    DAEMON_ACTIVE=false
    _install_flatpak
    _enable_daemon
}

do_uninstall() {
    confirm "${YELLOW}Remove Polychromatic and disable the daemon?${NC}" \
        || { ok "Cancelled"; exit 0; }
    _disable_daemon
    _remove_flatpak
}

do_repair() {
    step "Repairing missing components..."
    ! $POLY_INSTALLED && _install_flatpak || ok "$POLY_NAME already installed"
    _enable_daemon
}

# ── Menu (context-aware) ──────────────────────────────────────
PICK=""
case "$INSTALL_STATE" in
    none)
        menu \
            "Setup Polychromatic + daemon" \
            "Exit"
        case "$PICK" in
            1) do_setup ;;
            *) ok "Bye!"; exit 0 ;;
        esac
        ;;
    partial)
        menu \
            "Repair Polychromatic + daemon" \
            "Reinstall Polychromatic + restart daemon" \
            "Remove Polychromatic + disable daemon" \
            "Exit"
        case "$PICK" in
            1) do_repair ;;
            2) do_reinstall ;;
            3) do_uninstall; exit 0 ;;
            *) ok "Bye!"; exit 0 ;;
        esac
        ;;
    full)
        menu \
            "Reinstall Polychromatic + restart daemon" \
            "Remove Polychromatic + disable daemon" \
            "Exit"
        case "$PICK" in
            1) do_reinstall ;;
            2) do_uninstall; exit 0 ;;
            *) ok "Bye!"; exit 0 ;;
        esac
        ;;
esac

# ── Summary ───────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔══════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◆  Razer Setup — Done      ║${NC}"
say "${MAGENTA}${BOLD}╚══════════════════════════════╝${NC}"
say ""