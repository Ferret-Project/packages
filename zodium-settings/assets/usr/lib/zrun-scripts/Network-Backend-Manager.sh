#!/usr/bin/env bash
# ================================================================
#  Network-Backend-Toggle — Switch NM between iwd and wpa_supplicant
#  requires: bash, NetworkManager (nmcli), systemd
# ================================================================
# @tags: System

set -Eeuo pipefail

# ── Dependency check ──────────────────────────────────────────
command -v nmcli     &>/dev/null || { printf '%s\n' "⦻  nmcli is required" >&2; exit 1; }
command -v systemctl &>/dev/null || { printf '%s\n' "⦻  systemd is required" >&2; exit 1; }

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
skip() { say "  ${BOLD}↷${NC}  $* ${DIM}(skipped — not found)${NC}"; }

# ── Root / sudo abstraction ───────────────────────────────────
if [[ $EUID -eq 0 ]]; then
    SUDO=()
else
    command -v sudo &>/dev/null \
        || { printf '%s\n' "⦻  sudo is required when not running as root" >&2; exit 1; }
    SUDO=(sudo)
fi

# ── Flags ─────────────────────────────────────────────────────
ACTION=""      # use_iwd | use_wpa
ASSUME_YES=false

usage() {
    say "Usage: ${0##*/} [options] [backend]"
    say ""
    say "Backends:"
    say "  ${CYAN}iwd${NC}             switch to iwd"
    say "  ${CYAN}wpa_supplicant${NC}  switch to wpa_supplicant"
    say ""
    say "Options:"
    say "  ${CYAN}--yes${NC}           skip confirmation prompts"
    say "  ${CYAN}--help${NC}          show this message"
    say ""
    say "${YELLOW}◇${NC}  Switching will remove all saved Wi-Fi connections."
    say "  A NetworkManager restart or reboot is required to apply the change."
    say ""
    exit 0
}

while (( $# > 0 )); do
    case "$1" in
        iwd)
            [[ -n "$ACTION" ]] && fail "Only one backend may be specified"
            ACTION="use_iwd" ;;
        wpa_supplicant)
            [[ -n "$ACTION" ]] && fail "Only one backend may be specified"
            ACTION="use_wpa" ;;
        --yes)          ASSUME_YES=true ;;
        --help|-h)      usage ;;
        *) fail "Unknown option: $1  (try --help)" ;;
    esac
    shift
done

# ── Paths ─────────────────────────────────────────────────────
NM_CONF_DIR="/etc/NetworkManager/conf.d"
IWD_CONF="$NM_CONF_DIR/iwd.conf"

# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  Network Backend Toggle  ◈     ║${NC}"
say "${MAGENTA}${BOLD}╚════════════════════════════════════╝${NC}"
say ""

# ── Helpers ───────────────────────────────────────────────────
confirm() {
    local prompt=${1:-"Continue?"}
    $ASSUME_YES && return 0
    printf '%b [y/N]: ' "$prompt"
    read -r _ans
    [[ "$_ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ── State detection ───────────────────────────────────────────
IWD_CONF_ACTIVE=false
IWD_PKG=false
WPA_SERVICE_ENABLED=false

[[ -f "$IWD_CONF" ]] && grep -Eq '^[[:space:]]*wifi\.backend=iwd[[:space:]]*$' "$IWD_CONF" 2>/dev/null && IWD_CONF_ACTIVE=true
command -v iwctl &>/dev/null && IWD_PKG=true
systemctl is-enabled --quiet wpa_supplicant.service 2>/dev/null && WPA_SERVICE_ENABLED=true || true

if $IWD_CONF_ACTIVE; then
    CURRENT="iwd"
else
    CURRENT="wpa_supplicant"
fi

say "  Current backend: ${BOLD}${MAGENTA}$CURRENT${NC}"
say ""
warn "Switching will remove all saved Wi-Fi connections."
say ""

# ── Determine action interactively if not set via flag ────────
if [[ -z "$ACTION" ]]; then
    if [[ "$CURRENT" == "iwd" ]]; then
        say "  ${DIM}1)${NC}  ${CYAN}Switch to wpa_supplicant${NC}"
        say "  ${DIM}2)${NC}  ${CYAN}Exit${NC}"
        while :; do
            printf '\n  %b' "${DIM}choose:${NC} "
            read -r PICK
            say ""
            case "$PICK" in
                1) ACTION="use_wpa"; break ;;
                2) info "Bye!"; exit 0 ;;
                *) warn "Invalid choice — enter 1 or 2" ;;
            esac
        done
    else
        if ! $IWD_PKG; then
            fail "iwd is not installed — install it before switching to iwd backend"
        fi
        say "  ${DIM}1)${NC}  ${CYAN}Switch to iwd${NC}"
        say "  ${DIM}2)${NC}  ${CYAN}Exit${NC}"
        while :; do
            printf '\n  %b' "${DIM}choose:${NC} "
            read -r PICK
            say ""
            case "$PICK" in
                1) ACTION="use_iwd"; break ;;
                2) info "Bye!"; exit 0 ;;
                *) warn "Invalid choice — enter 1 or 2" ;;
            esac
        done
    fi
fi

# Guard: iwd flag used but iwd not installed
if [[ "$ACTION" == "use_iwd" ]] && ! $IWD_PKG; then
    fail "iwd is not installed — install it before switching to iwd backend"
fi

# ── Final confirmation ────────────────────────────────────────
TARGET=$( [[ "$ACTION" == "use_iwd" ]] && printf 'iwd' || printf 'wpa_supplicant' )
confirm "${RED}Switch to ${BOLD}${TARGET}${NC}${RED}? This will delete all saved Wi-Fi connections.${NC}" \
    || { info "Cancelled"; exit 0; }
say ""

# ── Remove saved Wi-Fi connections (by UUID) ──────────────────
remove_wifi_connections() {
    step "Removing saved Wi-Fi connections..."
    local uuid type count=0
    while IFS=: read -r uuid type; do
        [[ "$type" != "802-11-wireless" ]] && continue
        [[ -z "$uuid" ]] && continue
            if "${SUDO[@]}" nmcli connection delete uuid "$uuid" &>/dev/null; then
            (( count++ )) || true
        else
            warn "Failed to delete connection $uuid"
        fi
    done < <(nmcli -t -f UUID,TYPE connection show)
    if (( count > 0 )); then
        ok "Removed $count saved Wi-Fi connection(s)"
    else
        skip "No saved Wi-Fi connections found"
    fi
}

# ════════════════════════════════════════════════════════════════
#  SWITCH TO IWD
#  Per Arch wiki: NM manages iwd.service itself — do NOT enable it.
#  Write the backend conf and disable wpa_supplicant.service.
# ════════════════════════════════════════════════════════════════
if [[ "$ACTION" == "use_iwd" ]]; then

    step "Writing NM iwd backend config..."
    "${SUDO[@]}" mkdir -p "$NM_CONF_DIR"
    printf '[device]\nwifi.backend=iwd\n' | "${SUDO[@]}" tee "$IWD_CONF" > /dev/null
    ok "Config written → $IWD_CONF"

    step "Disabling wpa_supplicant.service..."
    if $WPA_SERVICE_ENABLED; then
            "${SUDO[@]}" systemctl disable --now wpa_supplicant.service
        ok "wpa_supplicant.service disabled"
    else
        skip "wpa_supplicant.service"
    fi

    remove_wifi_connections

    say ""
    say "${MAGENTA}${BOLD}╔══════════════════════════╗${NC}"
    say "${MAGENTA}${BOLD}║   ◆  Switched to iwd     ║${NC}"
    say "${MAGENTA}${BOLD}╚══════════════════════════╝${NC}"
    say "  Config : ${BOLD}$IWD_CONF${NC}"
    say "  Note   : NM manages iwd.service automatically"
    say ""
    warn "Restart NetworkManager or reboot to apply the backend change."
    say "  ${DIM}sudo systemctl restart NetworkManager${NC}"
    say ""

# ════════════════════════════════════════════════════════════════
#  SWITCH TO WPA_SUPPLICANT
#  Remove iwd.conf so NM falls back to its default (wpa_supplicant).
#  Re-enable wpa_supplicant.service.
# ════════════════════════════════════════════════════════════════
elif [[ "$ACTION" == "use_wpa" ]]; then

    if $IWD_CONF_ACTIVE; then
        step "Removing iwd backend config..."
            "${SUDO[@]}" rm -f "$IWD_CONF"
        if [[ -d "$NM_CONF_DIR" ]] && ! find "$NM_CONF_DIR" -mindepth 1 -print -quit | grep -q .; then
                    "${SUDO[@]}" rmdir "$NM_CONF_DIR"
        fi
        ok "iwd.conf removed"
    else
        skip "iwd.conf"
    fi

    step "Re-enabling wpa_supplicant.service..."
    if command -v wpa_supplicant &>/dev/null; then
            "${SUDO[@]}" systemctl enable --now wpa_supplicant.service
        ok "wpa_supplicant.service enabled"
    else
        skip "wpa_supplicant"
    fi

    remove_wifi_connections

    say ""
    say "${MAGENTA}${BOLD}╔══════════════════════════════════════╗${NC}"
    say "${MAGENTA}${BOLD}║   ◆  Switched to wpa_supplicant      ║${NC}"
    say "${MAGENTA}${BOLD}╚══════════════════════════════════════╝${NC}"
    say "  iwd.conf removed — NM will use wpa_supplicant"
    say ""
    warn "Restart NetworkManager or reboot to apply the backend change."
    say "  ${DIM}sudo systemctl restart NetworkManager${NC}"
    say ""

fi