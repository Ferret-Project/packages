#!/usr/bin/env bash
# ================================================================
#  VR-Support — WiVRn + Steam OpenXR setup for Zodium
#  Installs WiVRn Flatpak, configures Steam Flatpak overrides
#  for OpenXR/WiVRn passthrough
#  requires: flatpak
#  For use on zcore derivatives / any systemd+flatpak distro
# ================================================================
# @tags: Hardware

set -Eeuo pipefail

# ── Dependency check ──────────────────────────────────────────
command -v flatpak &>/dev/null || { echo "⦻  flatpak is required but not installed" >&2; exit 1; }

# ── Styling ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

say()  { printf "$@"; printf '\n'; }
info() { say "${CYAN}◈${NC}  $*"; }
ok()   { say "${GREEN}◆${NC}  $*"; }
warn() { say "${YELLOW}◇${NC}  $*"; }
fail() { say "${RED}⦻${NC}  $*" >&2; exit 1; }
ask()  { say "${MAGENTA}◉${NC}  $*"; }
skip() { say "  ${BOLD}↷${NC}  $* ${YELLOW}(skipped — already set)${NC}"; }

# ── IDs ───────────────────────────────────────────────────────
WIVRN_ID="io.github.wivrn.wivrn"
STEAM_ID="com.valvesoftware.Steam"

STEAM_OVERRIDES=(
    "--filesystem=xdg-run/wivrn:ro"
    "--filesystem=xdg-data/flatpak/app/io.github.wivrn.wivrn:ro"
    "--filesystem=/var/lib/flatpak/app/io.github.wivrn.wivrn:ro"
    "--filesystem=xdg-config/openxr:ro"
    "--filesystem=xdg-config/openvr:ro"
)

# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔════════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  VR Support Setup  ◈               ║${NC}"
say "${MAGENTA}${BOLD}║   WiVRn + Steam OpenXR configuration   ║${NC}"
say "${MAGENTA}${BOLD}╚════════════════════════════════════════╝${NC}"
say ""

# ── State detection ───────────────────────────────────────────
info "Scanning system for existing installation..."

HAS_WIVRN=false
HAS_STEAM=false
HAS_OVERRIDES=false

flatpak info "$WIVRN_ID" &>/dev/null && HAS_WIVRN=true
flatpak info "$STEAM_ID" &>/dev/null && HAS_STEAM=true

# Check if all overrides are already applied
if $HAS_STEAM; then
    EXISTING_OVERRIDES=$(flatpak override --user --show "$STEAM_ID" 2>/dev/null || true)
    ALL_SET=true
    for override in "${STEAM_OVERRIDES[@]}"; do
        fs="${override#--filesystem=}"
        fs="${fs%:ro}"
        if ! echo "$EXISTING_OVERRIDES" | grep -q "$fs"; then
            ALL_SET=false
            break
        fi
    done
    $ALL_SET && HAS_OVERRIDES=true
fi

INSTALLED_COUNT=0
$HAS_WIVRN     && (( INSTALLED_COUNT++ )) || true
$HAS_STEAM     && (( INSTALLED_COUNT++ )) || true
$HAS_OVERRIDES && (( INSTALLED_COUNT++ )) || true

# ── Report detected state ─────────────────────────────────────
say "  ${BOLD}Detection results:${NC}"
$HAS_WIVRN     && say "  ${GREEN}◆${NC} WiVRn Flatpak      — installed" \
               || say "  ${RED}◇${NC} WiVRn Flatpak      — not found"
$HAS_STEAM     && say "  ${GREEN}◆${NC} Steam Flatpak      — installed" \
               || say "  ${RED}◇${NC} Steam Flatpak      — not found"
$HAS_OVERRIDES && say "  ${GREEN}◆${NC} Steam overrides    — applied" \
               || say "  ${RED}◇${NC} Steam overrides    — not applied"
say ""

# ── Determine install state ───────────────────────────────────
if   [[ $INSTALLED_COUNT -eq 0 ]]; then
    STATE="none"
elif [[ $INSTALLED_COUNT -eq 3 ]]; then
    STATE="full"
else
    STATE="partial"
fi

# ── Mode prompt based on state ────────────────────────────────
case "$STATE" in

  none)
    say "  ${CYAN}◈${NC} No existing installation detected."
    say ""
    ask "What would you like to do?"
    say "  ${BOLD}1)${NC} Install"
    say "  ${BOLD}2)${NC} Cancel"
    say ""
    read -rp "  Enter choice [1/2]: " MODE
    case "$MODE" in
      1) ACTION="install" ;;
      *) info "Cancelled."; exit 0 ;;
    esac
    ;;

  full)
    WIVRN_VER=$(flatpak info "$WIVRN_ID" 2>/dev/null \
        | grep -i 'version' | awk '{print $NF}' || echo "unknown")
    say "  ${GREEN}◆${NC} Full installation detected — WiVRn ${BOLD}${WIVRN_VER}${NC}"
    say ""
    ask "What would you like to do?"
    say "  ${BOLD}1)${NC} Upgrade WiVRn to latest"
    say "  ${BOLD}2)${NC} Uninstall"
    say "  ${BOLD}3)${NC} Cancel"
    say ""
    read -rp "  Enter choice [1/2/3]: " MODE
    case "$MODE" in
      1) ACTION="install" ;;
      2) ACTION="uninstall" ;;
      *) info "Cancelled."; exit 0 ;;
    esac
    ;;

  partial)
    say "  ${YELLOW}◇${NC} Partial installation detected (${INSTALLED_COUNT}/3 components found)."
    say "    This may be a broken or incomplete setup."
    say ""
    ask "What would you like to do?"
    say "  ${BOLD}1)${NC} Repair / Complete installation"
    say "  ${BOLD}2)${NC} Remove all detected components"
    say "  ${BOLD}3)${NC} Cancel"
    say ""
    read -rp "  Enter choice [1/2/3]: " MODE
    case "$MODE" in
      1) ACTION="install" ;;
      2) ACTION="uninstall" ;;
      *) info "Cancelled."; exit 0 ;;
    esac
    ;;

esac
say ""

# ════════════════════════════════════════════════════════════════
#  INSTALL / UPGRADE
# ════════════════════════════════════════════════════════════════
if [[ "$ACTION" == "install" ]]; then

    # ── WiVRn ─────────────────────────────────────────────────
    if $HAS_WIVRN; then
        info "Upgrading WiVRn..."
        flatpak update -y "$WIVRN_ID" &>/dev/null \
            && ok "WiVRn upgraded" \
            || warn "WiVRn upgrade returned non-zero"
    else
        info "Installing WiVRn..."
        flatpak install -y flathub "$WIVRN_ID" \
            || fail "WiVRn install failed — is Flathub added as a remote?"
        ok "WiVRn installed"
    fi

    # ── Steam ─────────────────────────────────────────────────
    if $HAS_STEAM; then
        skip "Steam Flatpak"
    else
        info "Installing Steam..."
        flatpak install -y flathub "$STEAM_ID" \
            || fail "Steam install failed — is Flathub added as a remote?"
        ok "Steam installed"
    fi

    # ── Steam overrides ───────────────────────────────────────
    if $HAS_OVERRIDES; then
        skip "Steam OpenXR overrides"
    else
        info "Applying Steam Flatpak overrides for OpenXR/WiVRn..."
        flatpak override --user \
            "${STEAM_OVERRIDES[@]}" \
            "$STEAM_ID" \
            && ok "Steam overrides applied" \
            || fail "Failed to apply Steam overrides"
    fi

    # ── Summary ───────────────────────────────────────────────
    say ""
    say "${MAGENTA}${BOLD}╔═══════════════════════════════════╗${NC}"
    say "${MAGENTA}${BOLD}║   ◆  VR Support Setup Complete    ║${NC}"
    say "${MAGENTA}${BOLD}╚═══════════════════════════════════╝${NC}"
    say "  WiVRn  : ${BOLD}$WIVRN_ID${NC}"
    say "  Steam  : ${BOLD}$STEAM_ID${NC}"
    say ""
    say "  ${CYAN}◈${NC}  Connect your Quest headset and launch WiVRn to begin streaming."
    say "  ${CYAN}◈${NC}  Set WiVRn as your OpenXR runtime in Steam → Settings → VR."
    say ""

# ════════════════════════════════════════════════════════════════
#  UNINSTALL
# ════════════════════════════════════════════════════════════════
elif [[ "$ACTION" == "uninstall" ]]; then

    # ── Steam overrides ───────────────────────────────────────
    if $HAS_OVERRIDES; then
        info "Removing Steam OpenXR overrides..."
        for override in "${STEAM_OVERRIDES[@]}"; do
            fs="${override#--filesystem=}"
            flatpak override --user --nofilesystem="${fs%:ro}" "$STEAM_ID" 2>/dev/null || true
        done
        ok "Steam overrides removed"
    else
        skip "Steam overrides — not applied"
    fi

    # ── WiVRn ─────────────────────────────────────────────────
    if $HAS_WIVRN; then
        info "Removing WiVRn..."
        flatpak uninstall --delete-data -y "$WIVRN_ID" \
            && ok "WiVRn removed and data cleaned up" \
            || warn "WiVRn removal returned non-zero"
        info "Cleaning up unused runtimes..."
        flatpak uninstall --unused -y \
            && ok "Unused runtimes removed" \
            || true
    else
        skip "WiVRn — $WIVRN_ID"
    fi

    # ── Summary ───────────────────────────────────────────────
    say ""
    say "${MAGENTA}${BOLD}╔════════════════════════════╗${NC}"
    say "${MAGENTA}${BOLD}║   ◆  VR Support Removed    ║${NC}"
    say "${MAGENTA}${BOLD}╚════════════════════════════╝${NC}"
    say ""
    say "  ${YELLOW}◇${NC}  Steam remains installed. Only VR overrides and WiVRn were removed."
    say ""

fi