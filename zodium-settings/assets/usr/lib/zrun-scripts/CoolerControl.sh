#!/usr/bin/env bash
# ================================================================
#  CoolerControl Manager — Install, update, repair or remove
#  CoolerControlD AppImage
# ================================================================
# @tags: Applications

set -Eeuo pipefail

# ── Dependency checks ─────────────────────────────────────────
command -v curl &>/dev/null || { echo "⦻  curl is required but not installed" >&2; exit 1; }
command -v jq   &>/dev/null || { echo "⦻  jq is required but not installed"   >&2; exit 1; }

# ── Paths ─────────────────────────────────────────────────────
APP_DIR="$HOME/Applications/CoolerControl"
APPIMAGE="$APP_DIR/CoolerControlD.AppImage"
ICON="$APP_DIR/coolercontrol.svg"
LOCAL_MANAGER_DESKTOP="$HOME/.local/share/applications/coolercontrol-manager.desktop"
CLI_LAUNCHER="$HOME/.local/bin/coolercontrol"
VERSION_FILE="$APP_DIR/.version"
SCRIPT_PATH="$(readlink -f "$0")"

WEBUI_URL="http://localhost:11987"
ICON_URL="https://gitlab.com/coolercontrol/coolercontrol/-/raw/293c6a922788a31fff795f1767d040ec97b625c9/coolercontrol/icons/icon.svg"

# ── API ───────────────────────────────────────────────────────
GITLAB_API="https://gitlab.com/api/v4/projects/coolercontrol%2Fcoolercontrol/releases?per_page=1"
PERMALINK_URL="https://gitlab.com/coolercontrol/coolercontrol/-/releases/permalink/latest/downloads/packages/CoolerControlD-x86_64.AppImage"

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
FLAG_START_DAEMON=false
FLAG_WEB_UI=false
FLAG_CHECK_UPDATE=false
FLAG_INTERACTIVE=false

for arg in "$@"; do
    case "$arg" in
        --start-daemon)   FLAG_START_DAEMON=true ;;
        --web-ui)         FLAG_WEB_UI=true ;;
        --check-update)   FLAG_CHECK_UPDATE=true ;;
        --interactive)    FLAG_INTERACTIVE=true ;;
        --help|-h)
            say "Usage: ${0##*/} [flags]"
            say ""
            say "  ${CYAN}--start-daemon${NC}    start CoolerControlD with sudo"
            say "  ${CYAN}--web-ui${NC}          open the CoolerControl web UI"
            say "  ${CYAN}--check-update${NC}    check if a newer version is available"
            say "  ${CYAN}--interactive${NC}     prompt to upgrade if update is available"
            say ""
            say "  No flags — open the interactive install/manage menu"
            say ""
            exit 0 ;;
        *) fail "Unknown flag: $arg  (try --help)" ;;
    esac
done

if $FLAG_START_DAEMON || $FLAG_WEB_UI || $FLAG_CHECK_UPDATE || $FLAG_INTERACTIVE; then
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
say "${MAGENTA}${BOLD}╔══════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  CoolerControl Manager  ◈    ║${NC}"
say "${MAGENTA}${BOLD}╚══════════════════════════════════╝${NC}"
say ""

# ── Helpers ───────────────────────────────────────────────────
symlink_ok() {
    local link="$1" target="$2"
    [[ -L "$link" ]] || return 1
    local resolved
    resolved=$(readlink -f "$link" 2>/dev/null) || return 1
    [[ "$resolved" == "$(readlink -f "$target" 2>/dev/null)" ]]
}

file_contains() { [[ -f "$1" ]] && grep -qF "$2" "$1"; }

open_webui() {
    # 1. Native WebKit2GTK via python3 (GTK4 + WebKit 6.0)
    if command -v python3 &>/dev/null && python3 -c "
import gi
gi.require_version('Gtk','4.0')
gi.require_version('WebKit','6.0')
from gi.repository import Gtk, WebKit
" &>/dev/null 2>&1; then
        python3 <(cat << 'EOF_PY'
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('WebKit', '6.0')
from gi.repository import Gtk, WebKit
def on_activate(app):
    w = Gtk.ApplicationWindow(application=app, title='CoolerControl', default_width=1280, default_height=800)
    wv = WebKit.WebView()
    wv.load_uri('http://localhost:11987')
    w.set_child(wv)
    w.present()
app = Gtk.Application(application_id='org.coolercontrol.webui')
app.connect('activate', on_activate)
app.run([])
EOF_PY
        ) &>/dev/null &
        disown $!
        return 0
    fi

    # 2. Native WebKit2GTK via python3 (GTK3 + WebKit2 4.x)
    if command -v python3 &>/dev/null && python3 -c "
import gi
gi.require_version('Gtk','3.0')
gi.require_version('WebKit2','4.0')
from gi.repository import Gtk, WebKit2
" &>/dev/null 2>&1; then
        python3 <(cat << 'EOF_PY'
import gi
gi.require_version('Gtk', '3.0')
gi.require_version('WebKit2', '4.0')
from gi.repository import Gtk, WebKit2
w = Gtk.Window(title='CoolerControl', default_width=1280, default_height=800)
wv = WebKit2.WebView()
wv.load_uri('http://localhost:11987')
w.add(wv)
w.show_all()
w.connect('destroy', Gtk.main_quit)
Gtk.main()
EOF_PY
        ) &>/dev/null &
        disown $!
        return 0
    fi

    # 3. Fallback: let the system decide
    if command -v xdg-open &>/dev/null; then
        xdg-open "$WEBUI_URL" &>/dev/null &
        disown $!
        return 0
    fi
    warn "No webview or browser found — visit $WEBUI_URL manually"
}

# ── Scan installation state ───────────────────────────────────
HAS_APPIMAGE=false; [[ -f "$APPIMAGE" ]]  && HAS_APPIMAGE=true
HAS_ICON=false;     [[ -f "$ICON" ]]      && HAS_ICON=true
HAS_CLI=false;      [[ -f "$CLI_LAUNCHER" ]] && grep -qF "coolercontrol-manager" "$CLI_LAUNCHER" && HAS_CLI=true
HAS_VERSION=false;  INSTALLED_VERSION=""
if [[ -f "$VERSION_FILE" ]]; then
    HAS_VERSION=true
    INSTALLED_VERSION=$(< "$VERSION_FILE")
fi

HAS_MANAGER_DESKTOP=false
if file_contains "$LOCAL_MANAGER_DESKTOP" "Name=CoolerControl Manager" \
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

# ── Flag mode ─────────────────────────────────────────────────
if $ANY_FLAG; then

    if ! $HAS_APPIMAGE; then
        fail "CoolerControlD is not installed — run ${0##*/} to set it up"
    fi

    # --check-update / --interactive first so any upgrade is applied before starting
    if $FLAG_CHECK_UPDATE || $FLAG_INTERACTIVE; then
        step "Checking for updates..."
        API_JSON=$(curl -fsSL --retry 3 --retry-delay 2 "$GITLAB_API") \
            || { warn "Could not reach GitLab API"; exit 0; }
        LATEST_VERSION=$(jq -r '.[0].tag_name' <<<"$API_JSON")

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
                    curl -L --progress-bar -o "$tmp" "$PERMALINK_URL" \
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

    # --start-daemon after update so the freshest AppImage is used
    if $FLAG_START_DAEMON; then
        existing_pid=$(pgrep -f "CoolerControlD.AppImage" | head -n1 || true)
        if [[ -n "$existing_pid" ]]; then
            ok "Daemon already running  ${DIM}(PID $existing_pid)${NC}"
        else
            step "Starting CoolerControlD..."
            if ! sudo -v; then
                warn "sudo authentication failed — cannot start daemon"
            else
                sudo "$APPIMAGE" >/dev/null 2>&1 &
                daemon_pid=$!
                sleep 1
                if kill -0 "$daemon_pid" 2>/dev/null; then
                    ok "Daemon started  ${DIM}(PID $daemon_pid)${NC}"
                else
                    warn "Daemon may have failed to start — check AppImage integrity"
                fi
            fi
        fi
    fi

    # --web-ui after daemon so it has a moment to bind
    if $FLAG_WEB_UI; then
        step "Opening Web UI  ${DIM}($WEBUI_URL)${NC}..."
        open_webui
        ok "Web UI launched"
    fi

    say ""
    exit 0
fi

# ── Interactive menu mode ─────────────────────────────────────

step "Checking latest release..."
API_JSON=$(curl -fsSL --retry 3 --retry-delay 2 "$GITLAB_API") \
    || fail "Failed to query GitLab API — check your connection"
LATEST_VERSION=$(jq -r '.[0].tag_name' <<<"$API_JSON")
[[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]] \
    && fail "Could not detect latest version"
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
    [[ -n "$APP_DIR" && "$APP_DIR" == "$HOME/Applications/CoolerControl" ]] \
        || fail "Unexpected APP_DIR value, aborting"
    step "Removing CoolerControl..."
    rm -rf "$APP_DIR" "$CLI_LAUNCHER" "$LOCAL_MANAGER_DESKTOP"
    ok "CoolerControl removed"
    exit 0
}

# ── Terminal detection ────────────────────────────────────────
build_manager_exec() {
    local term
    for term in alacritty kitty konsole wezterm foot gnome-terminal kgx ghostty; do
        command -v "$term" &>/dev/null || continue
        case "$term" in
            wezterm)        printf '%s' "wezterm start -- $SCRIPT_PATH --check-update --interactive --start-daemon --web-ui" ;;
            gnome-terminal) printf '%s' "gnome-terminal -- $SCRIPT_PATH --check-update --interactive --start-daemon --web-ui" ;;
            kgx)            printf '%s' "kgx -- $SCRIPT_PATH --check-update --interactive --start-daemon --web-ui" ;;
            ghostty)        printf '%s' "ghostty -e $SCRIPT_PATH --check-update --interactive --start-daemon --web-ui" ;;
            *)              printf '%s' "$term -e $SCRIPT_PATH --check-update --interactive --start-daemon --web-ui" ;;
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
    curl -L --progress-bar -o "$tmp" "$PERMALINK_URL" \
        || fail "Failed to download AppImage"
    chmod +x "$tmp"
    mv -f "$tmp" "$APPIMAGE"
    _PARTIAL_APPIMAGE=""
    ok "AppImage downloaded"
}

install_icon() {
    info "Downloading icon..."
    if curl -fsSL -o "$ICON" "$ICON_URL"; then
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
Name=CoolerControl Manager
Comment=Start CoolerControl daemon and open Web UI
Exec=sh -c $(printf '%s' "$exec_line" | sed "s/'/'\\''/g; s/^/'/; s/$/'/")
Icon=$ICON
Terminal=false
Type=Application
Categories=System;Settings;
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
# CoolerControl CLI — check for updates, start daemon, open web UI, then exit
exec "$SCRIPT_PATH" --check-update --interactive --start-daemon --web-ui
EOF
    chmod +x "$CLI_LAUNCHER"
    [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] \
        && warn "~/.local/bin is not in your PATH — add it to use 'coolercontrol' from terminal"
    ok "CLI launcher ready  ${DIM}(run as: sudo coolercontrol)${NC}"
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
                1) SKIP_DOWNLOAD=true ;;
                2) do_remove ;;
                *) info "Bye!"; exit 0 ;;
            esac
        else
            menu "Update to $LATEST_VERSION" "Reinstall current ($INSTALLED_VERSION)" "Remove" "Exit"
            case "$PICK" in
                1) ;;
                2)
                    step "Fetching version-specific URL for $INSTALLED_VERSION..."
                    old_json=$(curl -fsSL --retry 3 --retry-delay 2 \
                        "https://gitlab.com/api/v4/projects/coolercontrol%2Fcoolercontrol/releases/$INSTALLED_VERSION") \
                        || fail "Could not fetch release info for $INSTALLED_VERSION"
                    old_url=$(jq -r '.assets.links[] | select(.name | test("CoolerControlD.*x86_64.*AppImage")) | .direct_asset_url' \
                        <<<"$old_json" | head -n1)
                    if [[ -z "$old_url" || "$old_url" == "null" ]]; then
                        warn "No version-specific URL found for $INSTALLED_VERSION — downloading latest instead"
                        old_url="$PERMALINK_URL"
                    fi
                    PERMALINK_URL="$old_url"
                    LATEST_VERSION="$INSTALLED_VERSION"
                    SKIP_DOWNLOAD=true
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

    [[ -n "$APP_DIR" && "$APP_DIR" == "$HOME/Applications/CoolerControl" ]] \
        || fail "Unexpected APP_DIR value, aborting cleanup"

    STASHED_APPIMAGE=""
    if $SKIP_DOWNLOAD && [[ -f "$APPIMAGE" ]]; then
        STASHED_APPIMAGE="$(mktemp /tmp/CoolerControlD.AppImage.XXXXXX)"
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
say "${MAGENTA}${BOLD}╔══════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◆  CoolerControl Setup Complete    ║${NC}"
say "${MAGENTA}${BOLD}╚══════════════════════════════════════╝${NC}"
say "  Version  : ${BOLD}$LATEST_VERSION${NC}"
say "  AppImage : ${BOLD}~/Applications/CoolerControl/CoolerControlD.AppImage${NC}"
say "  Manager  : ${BOLD}~/.local/share/applications/coolercontrol-manager.desktop${NC}"
say "  CLI      : ${BOLD}~/.local/bin/coolercontrol${NC}"
say ""
say "  ${YELLOW}◇${NC}  ${DIM}Daemon requires sudo — run with: sudo coolercontrol${NC}"
say "  ${YELLOW}◇${NC}  ${DIM}Web UI: $WEBUI_URL${NC}"
say ""