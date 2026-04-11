#!/usr/bin/env bash
# ================================================================
#  WinBoat Manager — Install, update, repair or remove WinBoat
#  By Zodium Project for use on zcore derivatives
# ================================================================
# @tags: Applications

set -Eeuo pipefail

# ── Dependency checks ─────────────────────────────────────────
command -v curl &>/dev/null || { echo "⦻  curl is required but not installed" >&2; exit 1; }
command -v jq   &>/dev/null || { echo "⦻  jq is required but not installed"   >&2; exit 1; }

# ── Paths ─────────────────────────────────────────────────────
APP_DIR="$HOME/Applications/WinBoat"
APPIMAGE="$APP_DIR/WinBoat.AppImage"
ICON="$APP_DIR/winboat_logo.svg"
LOCAL_MANAGER_DESKTOP="$HOME/.local/share/applications/winboat-manager.desktop"
CLI_LAUNCHER="$HOME/.local/bin/winboat"
VERSION_FILE="$APP_DIR/.version"
SCRIPT_PATH="$(readlink -f "$0")"

# ── API ───────────────────────────────────────────────────────
GITHUB_API="https://api.github.com/repos/TibixDev/winboat/releases/latest"

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
skip() { say "  ${BOLD}↷${NC}  ${DIM}$* — already present${NC}"; }

# ── Flag parsing ──────────────────────────────────────────────
FLAG_LAUNCH=false
FLAG_CHECK_UPDATE=false
FLAG_INTERACTIVE=false

for arg in "$@"; do
    case "$arg" in
        --launch)         FLAG_LAUNCH=true ;;
        --check-update)   FLAG_CHECK_UPDATE=true ;;
        --interactive)    FLAG_INTERACTIVE=true ;;
        --help|-h)
            say "Usage: ${0##*/} [flags]"
            say ""
            say "  ${CYAN}--launch${NC}          launch WinBoat (detached, prints PID)"
            say "  ${CYAN}--check-update${NC}    check if a newer version is available"
            say "  ${CYAN}--interactive${NC}     prompt to upgrade if update is available"
            say ""
            say "  No flags — open the interactive install/manage menu"
            say ""
            exit 0 ;;
        *) fail "Unknown flag: $arg  (try --help)" ;;
    esac
done

if $FLAG_LAUNCH || $FLAG_CHECK_UPDATE || $FLAG_INTERACTIVE; then
    ANY_FLAG=true
else
    ANY_FLAG=false
fi

# ── Interrupted-download cleanup ──────────────────────────────
_PARTIAL_APPIMAGE=""
trap '_cleanup_trap' EXIT
_cleanup_trap() {
    local code=$?
    if [[ $code -ne 0 && -n "$_PARTIAL_APPIMAGE" && -f "$_PARTIAL_APPIMAGE" ]]; then
        rm -f "$_PARTIAL_APPIMAGE"
        say "${YELLOW}◇${NC}  Removed incomplete download" >&2
    fi
}

# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔═════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  WinBoat Manager  ◈     ║${NC}"
say "${MAGENTA}${BOLD}╚═════════════════════════════╝${NC}"
say ""

# ── Helpers ───────────────────────────────────────────────────
file_contains() { [[ -f "$1" ]] && grep -qF "$2" "$1"; }

# ── Launch helper — fully detached ────────────────────────────
launch_winboat() {
    step "Launching WinBoat..."
    setsid "$APPIMAGE" &>/dev/null &
    local pid=$!
    disown "$pid"
    sleep 0.5
    if kill -0 "$pid" 2>/dev/null; then
        ok "WinBoat launched  ${DIM}(PID $pid)${NC}"
    else
        warn "WinBoat process exited immediately — AppImage may be broken"
    fi
}

# ── Scan installation state ───────────────────────────────────
HAS_APPIMAGE=false; [[ -f "$APPIMAGE" ]]  && HAS_APPIMAGE=true
HAS_ICON=false;     [[ -f "$ICON" ]]      && HAS_ICON=true
HAS_CLI=false;      [[ -f "$CLI_LAUNCHER" ]] && grep -qF "winboat-manager" "$CLI_LAUNCHER" && HAS_CLI=true
HAS_VERSION=false;  INSTALLED_VERSION=""
if [[ -f "$VERSION_FILE" ]]; then
    HAS_VERSION=true
    INSTALLED_VERSION=$(< "$VERSION_FILE")
fi

HAS_MANAGER_DESKTOP=false
if file_contains "$LOCAL_MANAGER_DESKTOP" "Name=WinBoat Manager" \
&& file_contains "$LOCAL_MANAGER_DESKTOP" "Exec="; then
    HAS_MANAGER_DESKTOP=true
fi

all_present() {
    $HAS_APPIMAGE && $HAS_ICON && $HAS_MANAGER_DESKTOP && $HAS_CLI && $HAS_VERSION
}
none_present() {
    ! $HAS_APPIMAGE && ! $HAS_ICON && ! $HAS_MANAGER_DESKTOP && ! $HAS_CLI && ! $HAS_VERSION
}

if   none_present; then INSTALL_STATE="none"
elif all_present;  then INSTALL_STATE="full"
else                    INSTALL_STATE="partial"
fi

# ── Flag mode: --launch / --check-update / --interactive ──────
if $ANY_FLAG; then

    if ! $HAS_APPIMAGE; then
        fail "WinBoat is not installed — run ${0##*/} to set it up"
    fi

    # --check-update / --interactive runs first so any upgrade is applied before launch
    if $FLAG_CHECK_UPDATE || $FLAG_INTERACTIVE; then
        step "Checking for updates..."
        API_JSON=$(curl -fsSL --retry 3 --retry-delay 2 "$GITHUB_API") \
            || { warn "Could not reach GitHub API"; exit 0; }
        LATEST_VERSION=$(jq -r '.tag_name' <<<"$API_JSON")
        LATEST_URL=$(jq -r '.assets[] | select(.name | endswith(".AppImage")) | .browser_download_url' \
            <<<"$API_JSON" | head -n1)

        if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
            ok "Up to date  ${DIM}$INSTALLED_VERSION${NC}"
        else
            warn "Update available  ${DIM}$INSTALLED_VERSION → $LATEST_VERSION${NC}"
            if $FLAG_INTERACTIVE; then
                printf '%b [y/N]: ' "  Upgrade to $LATEST_VERSION now?"
                read -r _ans
                say ""
                if [[ "$_ans" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    step "Downloading $LATEST_VERSION..."
                    tmp="$APPIMAGE.part"
                    _PARTIAL_APPIMAGE="$tmp"
                    curl -L --progress-bar -o "$tmp" "$LATEST_URL" \
                        && chmod +x "$tmp" \
                        && mv -f "$tmp" "$APPIMAGE" \
                        && echo "$LATEST_VERSION" > "$VERSION_FILE" \
                        && ok "Upgraded to $LATEST_VERSION" \
                        || warn "Upgrade failed"
                    _PARTIAL_APPIMAGE=""
                else
                    ok "Skipped"
                fi
            fi
        fi
    fi

    # --launch runs after update check/upgrade so the freshest AppImage is used
    if $FLAG_LAUNCH; then
        launch_winboat
    fi

    say ""
    exit 0
fi

# ── Interactive menu mode ─────────────────────────────────────

step "Checking latest release..."
API_JSON=$(curl -fsSL --retry 3 --retry-delay 2 "$GITHUB_API") \
    || fail "Failed to query GitHub API — check your connection"
LATEST_VERSION=$(jq -r '.tag_name' <<<"$API_JSON")
LATEST_URL=$(jq -r '.assets[] | select(.name | endswith(".AppImage")) | .browser_download_url' \
    <<<"$API_JSON" | head -n1)

[[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]] \
    && fail "Could not detect latest version"
[[ -z "$LATEST_URL"     || "$LATEST_URL"     == "null" ]] \
    && fail "Could not detect AppImage download URL"
say ""

# ── Status display ────────────────────────────────────────────
case "$INSTALL_STATE" in
    none)
        warn "Not installed  ${DIM}latest: $LATEST_VERSION${NC}"
        ;;
    full)
        if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
            ok "Up to date  ${DIM}$INSTALLED_VERSION${NC}"
        else
            warn "Update available  ${DIM}$INSTALLED_VERSION → $LATEST_VERSION${NC}"
        fi
        ;;
    partial)
        warn "Partial install  ${DIM}latest: $LATEST_VERSION${NC}"
        ! $HAS_APPIMAGE          && say "  ${RED}✗${NC}  ${DIM}AppImage${NC}"
        ! $HAS_ICON              && say "  ${RED}✗${NC}  ${DIM}Icon${NC}"
        ! $HAS_MANAGER_DESKTOP   && say "  ${RED}✗${NC}  ${DIM}Manager shortcut${NC}"
        ! $HAS_CLI               && say "  ${RED}✗${NC}  ${DIM}CLI launcher${NC}"
        ! $HAS_VERSION           && say "  ${RED}✗${NC}  ${DIM}Version record${NC}"
        ;;
esac
say ""

# ── Menu helper ───────────────────────────────────────────────
PICK=""
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

# ── Remove ────────────────────────────────────────────────────
do_remove() {
    [[ -n "$APP_DIR" && "$APP_DIR" == "$HOME/Applications/WinBoat" ]] \
        || fail "Unexpected APP_DIR value, aborting"
    step "Removing WinBoat..."
    rm -rf "$APP_DIR" "$CLI_LAUNCHER" "$LOCAL_MANAGER_DESKTOP"
    ok "WinBoat removed"
    exit 0
}

# ── Terminal detection ────────────────────────────────────────
build_manager_exec() {
    local term
    for term in alacritty kitty konsole wezterm foot gnome-terminal kgx ghostty xterm; do
        command -v "$term" &>/dev/null || continue
        case "$term" in
            wezterm)        printf '%s' "wezterm start -- $SCRIPT_PATH --launch --check-update --interactive" ;;
            gnome-terminal) printf '%s' "gnome-terminal -- $SCRIPT_PATH --launch --check-update --interactive" ;;
            kgx)            printf '%s' "kgx -- $SCRIPT_PATH --launch --check-update --interactive" ;;
            ghostty)        printf '%s' "ghostty -e $SCRIPT_PATH --launch --check-update --interactive" ;;
            *)              printf '%s' "$term -e $SCRIPT_PATH --launch --check-update --interactive" ;;
        esac
        return 0
    done
    return 1
}

# ── Install functions ─────────────────────────────────────────
download_appimage() {
    info "Downloading AppImage  ${DIM}($LATEST_VERSION)${NC}..."
    local tmp="$APPIMAGE.part"
    _PARTIAL_APPIMAGE="$tmp"
    curl -L --progress-bar -o "$tmp" "$LATEST_URL" \
        || fail "Failed to download AppImage"
    chmod +x "$tmp"
    mv -f "$tmp" "$APPIMAGE"
    _PARTIAL_APPIMAGE=""
    ok "AppImage downloaded"
}

install_icon() {
    info "Downloading icon..."
    if curl -fsSL -o "$ICON" \
            https://raw.githubusercontent.com/TibixDev/winboat/main/icons/winboat_logo.svg; then
        ok "Icon ready"
    else
        warn "Failed to fetch icon — desktop entry will have no icon"
    fi
}

install_manager_desktop() {
    local exec_line term_name
    if exec_line=$(build_manager_exec); then
        term_name=$(printf '%s' "$exec_line" | awk '{print $1}')
        mkdir -p "$(dirname "$LOCAL_MANAGER_DESKTOP")"
        cat > "$LOCAL_MANAGER_DESKTOP" <<EOF
[Desktop Entry]
Name=WinBoat Manager
Comment=Launch WinBoat and check for updates
Exec=sh -c $(printf '%s' "$exec_line" | sed "s/'/'\\''/g; s/^/'/; s/$/'/")
Icon=$ICON
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
EOF
        ok "Manager shortcut ready  ${DIM}($term_name)${NC}"
    else
        warn "No supported terminal found — skipping manager shortcut"
    fi
}

install_cli() {
    mkdir -p "$HOME/.local/bin"
    cat > "$CLI_LAUNCHER" <<EOF
#!/usr/bin/env bash
# WinBoat CLI — launch, check for updates, then exit
exec "$SCRIPT_PATH" --launch --check-update --interactive
EOF
    chmod +x "$CLI_LAUNCHER"
    [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] \
        && warn "~/.local/bin is not in your PATH — add it to use 'winboat' from terminal"
    ok "CLI launcher ready  ${DIM}(run: winboat)${NC}"
}

# ── Menu dispatch ─────────────────────────────────────────────
SKIP_DOWNLOAD=false

case "$INSTALL_STATE" in
    none)
        menu "Install ($LATEST_VERSION)" "Exit"
        case "$PICK" in
            1) ;;
            *) info "Bye!"; exit 0 ;;
        esac
        ;;
    partial)
        menu "Repair" "Reinstall ($LATEST_VERSION)" "Remove" "Exit"
        case "$PICK" in
            1) step "Repairing..."; mkdir -p "$APP_DIR" ;;
            2)
                # Reuse existing AppImage if it's already the latest version
                if $HAS_APPIMAGE && [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
                    SKIP_DOWNLOAD=true
                fi
                ;;
            3) do_remove ;;
            *) info "Bye!"; exit 0 ;;
        esac
        ;;
    full)
        if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
            menu "Reinstall ($INSTALLED_VERSION)" "Remove" "Exit"
            case "$PICK" in
                1) SKIP_DOWNLOAD=true ;;  # already latest — reuse existing AppImage
                2) do_remove ;;
                *) info "Bye!"; exit 0 ;;
            esac
        else
            menu "Update to $LATEST_VERSION" "Reinstall current ($INSTALLED_VERSION)" "Remove" "Exit"
            case "$PICK" in
                1) ;;
                2)
                    step "Fetching info for $INSTALLED_VERSION..."
                    old_json=$(curl -fsSL --retry 3 --retry-delay 2 \
                        "https://api.github.com/repos/TibixDev/winboat/releases/tags/$INSTALLED_VERSION") \
                        || fail "Could not fetch release info for $INSTALLED_VERSION"
                    old_url=$(jq -r '.assets[] | select(.name | endswith(".AppImage")) | .browser_download_url' \
                        <<<"$old_json" | head -n1)
                    [[ -z "$old_url" || "$old_url" == "null" ]] \
                        && fail "Could not resolve download URL for $INSTALLED_VERSION"
                    LATEST_URL="$old_url"
                    LATEST_VERSION="$INSTALLED_VERSION"
                    SKIP_DOWNLOAD=true  # reinstalling same version — reuse existing AppImage
                    ;;
                3) do_remove ;;
                *) info "Bye!"; exit 0 ;;
            esac
        fi
        ;;
esac

# ── Repair: only touch missing/broken pieces ──────────────────
if [[ "$INSTALL_STATE" == "partial" && "$PICK" == "1" ]]; then

    if $HAS_APPIMAGE;        then skip "AppImage";         else download_appimage;       fi
    if $HAS_ICON;            then skip "Icon";             else install_icon;            fi
    if $HAS_CLI;             then skip "CLI launcher";     else install_cli;             fi
    if $HAS_MANAGER_DESKTOP; then skip "Manager shortcut"; else install_manager_desktop; fi

    if $HAS_VERSION; then
        skip "Version record"
    else
        echo "$LATEST_VERSION" > "$VERSION_FILE"
        ok "Version record written"
    fi

    ok "Repair complete"

# ── Full clean install / update / reinstall ───────────────────
else

    [[ -n "$APP_DIR" && "$APP_DIR" == "$HOME/Applications/WinBoat" ]] \
        || fail "Unexpected APP_DIR value, aborting cleanup"

    # Stash the AppImage before wiping if we're going to reuse it
    STASHED_APPIMAGE=""
    if $SKIP_DOWNLOAD && [[ -f "$APPIMAGE" ]]; then
        STASHED_APPIMAGE="$(mktemp /tmp/WinBoat.AppImage.XXXXXX)"
        cp "$APPIMAGE" "$STASHED_APPIMAGE"
    fi

    step "Removing old installation..."
    rm -rf "$APP_DIR" "$CLI_LAUNCHER" "$LOCAL_MANAGER_DESKTOP"
    mkdir -p "$APP_DIR"

    if $SKIP_DOWNLOAD && [[ -n "$STASHED_APPIMAGE" ]]; then
        info "Reusing existing AppImage  ${DIM}($LATEST_VERSION)${NC}..."
        mv "$STASHED_APPIMAGE" "$APPIMAGE"
        chmod +x "$APPIMAGE"
        ok "AppImage ready"
    else
        download_appimage
    fi

    install_icon
    install_manager_desktop
    install_cli

    echo "$LATEST_VERSION" > "$VERSION_FILE"

fi

# ── Refresh desktop database ──────────────────────────────────
command -v update-desktop-database &>/dev/null \
    && update-desktop-database "$HOME/.local/share/applications" &>/dev/null || true

# ── Summary ───────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔═════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◆  WinBoat Setup Completed   ◆    ║${NC}"
say "${MAGENTA}${BOLD}╚═════════════════════════════════════╝${NC}"
say "  Version  : ${BOLD}$LATEST_VERSION${NC}"
say "  AppImage : ${BOLD}~/Applications/WinBoat/WinBoat.AppImage${NC}"
say "  Manager  : ${BOLD}~/.local/share/applications/winboat-manager.desktop${NC}"
say "  CLI      : ${BOLD}~/.local/bin/winboat${NC}"
say ""