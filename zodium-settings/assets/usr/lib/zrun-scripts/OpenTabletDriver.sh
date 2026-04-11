#!/usr/bin/env bash
# ================================================================
#  OpenTabletDriver-Setup — Install, Upgrade, or Remove OTD
#  Detects current state before acting — never blindly executes
#  requires: curl, tar, flatpak, systemd
#  For use on zcore derivatives / any systemd+flatpak distro
# ================================================================
# @tags: Hardware

set -Eeuo pipefail

# ── Dependency check ──────────────────────────────────────────
command -v curl      &>/dev/null || { printf '%s\n' "⦻  curl is required" >&2; exit 1; }
command -v tar       &>/dev/null || { printf '%s\n' "⦻  tar is required" >&2; exit 1; }
command -v flatpak   &>/dev/null || { printf '%s\n' "⦻  flatpak is required" >&2; exit 1; }
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

# ── Root check ────────────────────────────────────────────────
# This script installs a user-level systemd service — running as root
# would put it in root's home and not the desktop user's session.
if [[ $EUID -eq 0 ]]; then
    printf '%s\n' "⦻  Do not run this script as root." >&2
    printf '%s\n' "   Run it as your normal user — sudo will be used automatically for system changes." >&2
    exit 1
fi
command -v sudo &>/dev/null     || { printf '%s\n' "⦻  sudo is required" >&2; exit 1; }
SUDO=(sudo)

# ── Paths ─────────────────────────────────────────────────────
FLATPAK_ID="net.opentabletdriver.OpenTabletDriver"
UDEV_RULES="/etc/udev/rules.d/70-opentabletdriver.rules"
MODPROBE_CONF="/etc/modprobe.d/blacklist-opentabletdriver.conf"
SERVICE_FILE="$HOME/.config/systemd/user/opentabletdriver.service"

# ── Flags ─────────────────────────────────────────────────────
ACTION=""      # install | uninstall
ASSUME_YES=false

usage() {
    say "Usage: ${0##*/} [options] [action]"
    say ""
    say "Actions:"
    say "  ${CYAN}install${NC}      install or upgrade OpenTabletDriver"
    say "  ${CYAN}uninstall${NC}    remove all OTD components"
    say ""
    say "Options:"
    say "  ${CYAN}--yes${NC}        skip confirmation prompts"
    say "  ${CYAN}--help${NC}       show this message"
    say ""
    exit 0
}

while (( $# > 0 )); do
    case "$1" in
        install|uninstall)
            [[ -n "$ACTION" ]] && fail "Only one action may be specified"
            ACTION="$1" ;;
        --yes)     ASSUME_YES=true ;;
        --help|-h) usage ;;
        *) fail "Unknown option: $1  (try --help)" ;;
    esac
    shift
done


# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔══════════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║    ◈  OpenTabletDriver Installer  ◈      ║${NC}"
say "${MAGENTA}${BOLD}║    Open-source user-mode tablet driver   ║${NC}"
say "${MAGENTA}${BOLD}╚══════════════════════════════════════════╝${NC}"
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
        printf '\n  %b' "${DIM}choose:${NC} "
        read -r PICK
        say ""
        [[ "$PICK" =~ ^[1-9][0-9]*$ ]] && (( PICK >= 1 && PICK <= max )) && break
        warn "Invalid choice — enter a number between 1 and $max"
    done
}

# ── State detection ───────────────────────────────────────────
info "Scanning system for existing installation..."

HAS_FLATPAK=false
HAS_UDEV=false
HAS_MODPROBE=false
HAS_SERVICE=false
HAS_SERVICE_ENABLED=false

# Detect install scope for existing package, or pick best scope for fresh install
FLATPAK_SCOPE="--system"
if flatpak info --system "$FLATPAK_ID" &>/dev/null; then
    HAS_FLATPAK=true
    FLATPAK_SCOPE="--system"
elif flatpak info --user "$FLATPAK_ID" &>/dev/null; then
    HAS_FLATPAK=true
    FLATPAK_SCOPE="--user"
else
    # Fresh install — prefer the scope where Flathub is already configured
    if flatpak remotes --user 2>/dev/null | awk '{print $1}' | grep -qx flathub; then
        FLATPAK_SCOPE="--user"
    elif flatpak remotes --system 2>/dev/null | awk '{print $1}' | grep -qx flathub; then
        FLATPAK_SCOPE="--system"
    fi
fi
[[ -f "$UDEV_RULES" ]]                                           && HAS_UDEV=true
[[ -f "$MODPROBE_CONF" ]]                                        && HAS_MODPROBE=true
[[ -f "$SERVICE_FILE" ]]                                         && HAS_SERVICE=true
systemctl --user is-enabled opentabletdriver.service &>/dev/null && HAS_SERVICE_ENABLED=true || true

INSTALLED_COUNT=0
$HAS_FLATPAK  && (( INSTALLED_COUNT++ )) || true
$HAS_UDEV     && (( INSTALLED_COUNT++ )) || true
$HAS_MODPROBE && (( INSTALLED_COUNT++ )) || true
$HAS_SERVICE  && (( INSTALLED_COUNT++ )) || true

# ── Report detected state ─────────────────────────────────────
say "  ${BOLD}Detection results:${NC}"
if $HAS_FLATPAK;  then say "  ${GREEN}◆${NC} Flatpak package    — installed"
                  else say "  ${RED}◇${NC} Flatpak package    — not found"; fi
if $HAS_UDEV;     then say "  ${GREEN}◆${NC} udev rules         — present"
                  else say "  ${RED}◇${NC} udev rules         — not found"; fi
if $HAS_MODPROBE; then say "  ${GREEN}◆${NC} Module blacklist   — present"
                  else say "  ${RED}◇${NC} Module blacklist   — not found"; fi
if $HAS_SERVICE;  then say "  ${GREEN}◆${NC} Systemd service    — present"
                  else say "  ${RED}◇${NC} Systemd service    — not found"; fi
say ""

if   (( INSTALLED_COUNT == 0 )); then STATE="none"
elif (( INSTALLED_COUNT == 4 )); then STATE="full"
else                                  STATE="partial"
fi

# ── Determine action interactively if not set via flag ────────
if [[ -z "$ACTION" ]]; then
    case "$STATE" in
        none)
            say "  ${CYAN}◈${NC} No existing installation detected."
            say ""
            menu "Install" "Exit"
            case "$PICK" in
                1) ACTION="install" ;;
                *) info "Bye!"; exit 0 ;;
            esac
            ;;
        full)
            INSTALLED_VER=$(flatpak info "$FLATPAK_SCOPE" "$FLATPAK_ID" 2>/dev/null \
                | awk -F': ' '/[Vv]ersion/{print $2; exit}')
            INSTALLED_VER=${INSTALLED_VER:-unknown}
            say "  ${GREEN}◆${NC} Full installation detected — version ${BOLD}${INSTALLED_VER}${NC}"
            say ""
            menu "Upgrade to latest" "Uninstall" "Exit"
            case "$PICK" in
                1) ACTION="install" ;;
                2) ACTION="uninstall" ;;
                *) info "Bye!"; exit 0 ;;
            esac
            ;;
        partial)
            say "  ${YELLOW}◇${NC} Partial installation detected ${DIM}(${INSTALLED_COUNT}/4 components found)${NC}"
            say "    This may be a broken or incomplete install."
            say ""
            menu "Repair / Complete installation" "Remove all detected components" "Exit"
            case "$PICK" in
                1) ACTION="install" ;;
                2) ACTION="uninstall" ;;
                *) info "Bye!"; exit 0 ;;
            esac
            ;;
    esac
    say ""
fi

[[ -n "$ACTION" ]] || fail "No action selected"

# ════════════════════════════════════════════════════════════════
#  INSTALL / UPGRADE
# ════════════════════════════════════════════════════════════════
if [[ "$ACTION" == "install" ]]; then

    # ── Fetch latest release info ─────────────────────────────
    step "Fetching latest OTD release info..."
    API_JSON=$(curl -fsSL "https://api.github.com/repos/OpenTabletDriver/OpenTabletDriver/releases/latest") \
        || fail "Failed to query GitHub API (check your internet connection)"

    # Use grep + sed rather than -P for wider portability
    LATEST_VERSION=$(printf '%s' "$API_JSON" \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/') \
        || fail "Could not parse latest version from GitHub API response"
    [[ -n "$LATEST_VERSION" ]] || fail "tag_name was empty in GitHub API response"
    ok "Latest version: ${BOLD}$LATEST_VERSION${NC}"

    TARBALL_URL=$(printf '%s' "$API_JSON" \
        | grep '"browser_download_url"' \
        | grep -i 'opentabletdriver.*\.tar\.gz' \
        | head -1 \
        | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/') \
        || fail "Could not find tarball download URL in GitHub API response"
    [[ -n "$TARBALL_URL" ]] || fail "No matching tarball found in GitHub release assets"

    # ── Download + extract tarball ────────────────────────────
    OTD_TMPDIR="$(mktemp -d)"
    trap 'rm -rf -- "$OTD_TMPDIR"' EXIT

    step "Downloading release tarball..."
    curl -fsSL "$TARBALL_URL" \
        | tar --strip-components=1 -xzf - -C "$OTD_TMPDIR" \
        || fail "Failed to download or extract tarball"

    # ── udev rules ────────────────────────────────────────────
    UDEV_SRC=$(find "$OTD_TMPDIR" -type f -name '*opentabletdriver.rules' -print -quit)
    if [[ -n "$UDEV_SRC" ]]; then
        step "Installing udev rules..."
        "${SUDO[@]}" install -D -m 644 "$UDEV_SRC" "$UDEV_RULES"
        "${SUDO[@]}" udevadm control --reload-rules
        "${SUDO[@]}" udevadm trigger
        ok "udev rules installed → $UDEV_RULES"
    else
        warn "udev rules not found in tarball — skipping"
    fi

    # ── Kernel module blacklist ───────────────────────────────
    say ""
    warn "This will blacklist kernel tablet drivers: ${BOLD}hid_uclogic${NC}${YELLOW} and ${BOLD}wacom${NC}"
    warn "Other tablet devices using these drivers may stop working until removed or rebooted."
    if confirm "Apply kernel module blacklist?"; then
        say ""
        step "Writing kernel module blacklist..."
        printf '# Managed by OpenTabletDriver-Setup\nblacklist hid_uclogic\nblacklist wacom\n' \
            | "${SUDO[@]}" tee "$MODPROBE_CONF" > /dev/null
        ok "Module blacklist written → $MODPROBE_CONF"
    else
        say ""
        warn "Kernel blacklist skipped — some tablets may not work correctly"
        warn "until ${BOLD}hid_uclogic${NC}${YELLOW} and ${BOLD}wacom${NC}${YELLOW} kernel drivers are manually disabled."
    fi

    # ── Flatpak install / upgrade ─────────────────────────────
    if $HAS_FLATPAK; then
        step "Upgrading Flatpak package..."
        flatpak "$FLATPAK_SCOPE" update -y "$FLATPAK_ID" \
            || fail "Flatpak upgrade failed"
        ok "Flatpak package upgraded"
    else
        step "Installing Flatpak package..."
        if [[ "$FLATPAK_SCOPE" == "--user" ]]; then
            flatpak remotes --user 2>/dev/null | awk '{print $1}' | grep -qx flathub \
                || fail "Flathub user remote not found — add it first: flatpak remote-add --user flathub https://flathub.org/repo/flathub.flatpakrepo"
        else
            flatpak remotes --system 2>/dev/null | awk '{print $1}' | grep -qx flathub \
                || fail "Flathub system remote not found — add it first: flatpak remote-add --system flathub https://flathub.org/repo/flathub.flatpakrepo"
        fi
        flatpak "$FLATPAK_SCOPE" install -y flathub "$FLATPAK_ID" \
            || fail "Flatpak install failed"
        ok "Flatpak package installed"
    fi

    # ── Systemd user service ──────────────────────────────────
    # Prefer service file from release tarball; fall back to Flathub repo
    SERVICE_SRC=$(find "$OTD_TMPDIR" -type f -name 'opentabletdriver.service' -print -quit)

    step "Installing systemd user service..."
    mkdir -p "$HOME/.config/systemd/user"

    if [[ -n "$SERVICE_SRC" ]]; then
        install -D -m 644 "$SERVICE_SRC" "$SERVICE_FILE"
        ok "Service file installed from release tarball"
    else
        # Tarball didn't include it — fetch from Flathub packaging repo
        SERVICE_URL="https://raw.githubusercontent.com/flathub/net.opentabletdriver.OpenTabletDriver/refs/heads/master/scripts/opentabletdriver.service"
        warn "Service file not in tarball — fetching from Flathub repo"
        curl -fsSL "$SERVICE_URL" -o "$SERVICE_FILE" \
            || fail "Failed to download service file"
        ok "Service file downloaded"
    fi

    systemctl --user show-environment &>/dev/null         || fail "User systemd session is not available — run this from a logged-in desktop session"

    systemctl --user daemon-reload

    if $HAS_SERVICE_ENABLED; then
        step "Restarting service..."
        systemctl --user restart opentabletdriver.service
        ok "Service restarted"
    else
        systemctl --user enable --now opentabletdriver.service
        ok "Service enabled and started"
    fi

    trap - EXIT
    rm -rf -- "$OTD_TMPDIR"

    # ── Summary ───────────────────────────────────────────────
    say ""
    say "${MAGENTA}${BOLD}╔═══════════════════════════════╗${NC}"
    say "${MAGENTA}${BOLD}║   ◆  Installation Complete    ║${NC}"
    say "${MAGENTA}${BOLD}╚═══════════════════════════════╝${NC}"
    say "  Version   : ${BOLD}$LATEST_VERSION${NC}"
    say "  Flatpak   : ${BOLD}$FLATPAK_ID${NC}"
    say "  udev      : ${BOLD}$UDEV_RULES${NC}"
    say "  Blacklist : ${BOLD}$MODPROBE_CONF${NC}"
    say "  Service   : ${BOLD}opentabletdriver.service (user)${NC}"
    say ""
    warn "A reboot is recommended to apply kernel module changes."
    say ""

# ════════════════════════════════════════════════════════════════
#  UNINSTALL
# ════════════════════════════════════════════════════════════════
elif [[ "$ACTION" == "uninstall" ]]; then

    confirm "${RED}Remove OpenTabletDriver and all related components?${NC}" \
        || { info "Cancelled"; exit 0; }
    say ""

    # ── Service ───────────────────────────────────────────────
    if $HAS_SERVICE_ENABLED; then
        step "Stopping and disabling service..."
        systemctl --user disable --now opentabletdriver.service
        ok "Service stopped and disabled"
    else
        skip "opentabletdriver.service (not enabled)"
    fi

    if $HAS_SERVICE; then
        step "Removing service file..."
        rm -f "$SERVICE_FILE"
        systemctl --user daemon-reload
        ok "Service file removed"
    else
        skip "Service file — $SERVICE_FILE"
    fi

    # ── Flatpak ───────────────────────────────────────────────
    if $HAS_FLATPAK; then
        step "Removing Flatpak package..."
        flatpak "$FLATPAK_SCOPE" remove -y "$FLATPAK_ID" \
            || fail "Flatpak removal failed"
        ok "Flatpak package removed"
    else
        skip "Flatpak package — $FLATPAK_ID"
    fi

    # ── udev rules ────────────────────────────────────────────
    if $HAS_UDEV; then
        step "Removing udev rules..."
        "${SUDO[@]}" rm -f "$UDEV_RULES"
        "${SUDO[@]}" udevadm control --reload-rules
        "${SUDO[@]}" udevadm trigger
        ok "udev rules removed"
    else
        skip "udev rules — $UDEV_RULES"
    fi

    # ── Module blacklist ──────────────────────────────────────
    if $HAS_MODPROBE; then
        step "Removing module blacklist..."
        "${SUDO[@]}" rm -f "$MODPROBE_CONF"
        ok "Module blacklist removed"
    else
        skip "Module blacklist — $MODPROBE_CONF"
    fi

    # ── Summary ───────────────────────────────────────────────
    say ""
    say "${MAGENTA}${BOLD}╔════════════════════════════╗${NC}"
    say "${MAGENTA}${BOLD}║   ◆  Uninstall Complete    ║${NC}"
    say "${MAGENTA}${BOLD}╚════════════════════════════╝${NC}"
    say ""
    warn "A reboot is recommended to fully unload kernel changes."
    say ""

fi