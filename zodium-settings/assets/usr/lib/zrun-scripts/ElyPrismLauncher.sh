#!/usr/bin/env bash
# ================================================================
#  ElyPrismLauncher Setup — Install, repair or remove
#  Qt6 Portable build (x86_64 or aarch64)
# ================================================================
# @tags: Applications

set -Eeuo pipefail

# ── Dependency checks ─────────────────────────────────────────
command -v curl &>/dev/null || { echo "⦻  curl is required but not installed" >&2; exit 1; }
command -v jq   &>/dev/null || { echo "⦻  jq is required but not installed"   >&2; exit 1; }
command -v tar  &>/dev/null || { echo "⦻  tar is required but not installed"   >&2; exit 1; }

# ── Arch detection ────────────────────────────────────────────
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)         ASSET_ARCH="" ;;         # ElyPrismLauncher-Linux-Qt6-Portable-{ver}.tar.gz
    aarch64|arm64)  ASSET_ARCH="aarch64-" ;; # ElyPrismLauncher-Linux-aarch64-Qt6-Portable-{ver}.tar.gz
    *) echo "⦻  Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

# ── Paths ─────────────────────────────────────────────────────
APP_DIR="$HOME/Applications/ElyPrismLauncher"
LAUNCHER="$APP_DIR/ElyPrismLauncher"
ICON="$APP_DIR/share/icons/hicolor/scalable/apps/io.github.elyprismlauncher.ElyPrismLauncher.svg"
LOCAL_DESKTOP="$HOME/.local/share/applications/elyprismlauncher.desktop"
CLI_LAUNCHER="$HOME/.local/bin/elyprismlauncher"
VERSION_FILE="$APP_DIR/.version"
SCRIPT_PATH="$(readlink -f "$0")"

# ── API ───────────────────────────────────────────────────────
GITHUB_API="https://api.github.com/repos/ElyPrismLauncher/Launcher/releases/latest"

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

for arg in "$@"; do
    case "$arg" in
        --launch)  FLAG_LAUNCH=true ;;
        --help|-h)
            say "Usage: ${0##*/} [flags]"
            say ""
            say "  ${CYAN}--launch${NC}    launch ElyPrismLauncher (detached, prints PID)"
            say ""
            say "  No flags — open the interactive install/manage menu"
            say ""
            exit 0 ;;
        *) fail "Unknown flag: $arg  (try --help)" ;;
    esac
done

# ── Interrupted-download cleanup ──────────────────────────────
_PARTIAL=""
trap '_cleanup_trap' EXIT
_cleanup_trap() {
    local code=$?
    if [[ $code -ne 0 && -n "$_PARTIAL" && -e "$_PARTIAL" ]]; then
        rm -rf "$_PARTIAL"
        say "${YELLOW}◇${NC}  Removed incomplete download" >&2
    fi
}

# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔════════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  ElyPrismLauncher Setup  ◈         ║${NC}"
say "${MAGENTA}${BOLD}╚════════════════════════════════════════╝${NC}"
say ""

# ── Helpers ───────────────────────────────────────────────────
file_contains() { [[ -f "$1" ]] && grep -qF "$2" "$1"; }

# ── Launch helper — fully detached ────────────────────────────
launch_epl() {
    step "Launching ElyPrismLauncher..."
    setsid "$LAUNCHER" &>/dev/null &
    local pid=$!
    disown "$pid"
    sleep 0.5
    if kill -0 "$pid" 2>/dev/null; then
        ok "ElyPrismLauncher launched  ${DIM}(PID $pid)${NC}"
    else
        warn "Process exited immediately — ElyPrismLauncher may be broken or missing a dependency"
    fi
}

# ── Scan installation state ───────────────────────────────────
HAS_LAUNCHER=false; [[ -x "$LAUNCHER" ]] && HAS_LAUNCHER=true
HAS_ICON=false;     [[ -f "$ICON" ]]     && HAS_ICON=true
HAS_CLI=false;      [[ -f "$CLI_LAUNCHER" ]] && grep -qF "ElyPrismLauncher-Setup" "$CLI_LAUNCHER" && HAS_CLI=true
HAS_VERSION=false;  INSTALLED_VERSION=""
if [[ -f "$VERSION_FILE" ]]; then
    HAS_VERSION=true
    INSTALLED_VERSION=$(< "$VERSION_FILE")
fi

HAS_DESKTOP=false
if file_contains "$LOCAL_DESKTOP" "Name=ElyPrismLauncher" \
&& file_contains "$LOCAL_DESKTOP" "Exec="; then
    HAS_DESKTOP=true
fi

all_present() {
    $HAS_LAUNCHER && $HAS_ICON && $HAS_DESKTOP && $HAS_CLI && $HAS_VERSION
}
none_present() {
    ! $HAS_LAUNCHER && ! $HAS_ICON && ! $HAS_DESKTOP && ! $HAS_CLI && ! $HAS_VERSION
}

if   none_present; then INSTALL_STATE="none"
elif all_present;  then INSTALL_STATE="full"
else                    INSTALL_STATE="partial"
fi

# ── Flag mode: --launch ───────────────────────────────────────
if $FLAG_LAUNCH; then
    if ! $HAS_LAUNCHER; then
        fail "ElyPrismLauncher is not installed — run ${0##*/} to set it up"
    fi
    launch_epl
    say ""
    exit 0
fi

# ── Interactive menu mode ─────────────────────────────────────

step "Checking latest release..."
API_JSON=$(curl -fsSL --retry 3 --retry-delay 2 "$GITHUB_API") \
    || fail "Failed to query GitHub API — check your connection"
LATEST_VERSION=$(jq -r '.tag_name' <<<"$API_JSON")
LATEST_URL=$(jq -r --arg arch "$ASSET_ARCH" \
    '.assets[] | select(.name | test("Linux-" + $arch + "Qt6-Portable")) | select(.name | endswith(".tar.gz")) | .browser_download_url' \
    <<<"$API_JSON" | head -n1)

[[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]] \
    && fail "Could not detect latest version"
[[ -z "$LATEST_URL"     || "$LATEST_URL"     == "null" ]] \
    && fail "Could not detect Qt6 Portable download URL for $ARCH"
say ""

# ── Status display ────────────────────────────────────────────
case "$INSTALL_STATE" in
    none)
        warn "Not installed  ${DIM}latest: $LATEST_VERSION  arch: $ARCH${NC}"
        ;;
    full)
        ok "Installed  ${DIM}$INSTALLED_VERSION  arch: $ARCH${NC}"
        ;;
    partial)
        warn "Partial install  ${DIM}latest: $LATEST_VERSION  arch: $ARCH${NC}"
        ! $HAS_LAUNCHER && say "  ${RED}✗${NC}  ${DIM}ElyPrismLauncher${NC}"
        ! $HAS_ICON     && say "  ${RED}✗${NC}  ${DIM}Icon${NC}"
        ! $HAS_DESKTOP  && say "  ${RED}✗${NC}  ${DIM}Desktop shortcut${NC}"
        ! $HAS_CLI      && say "  ${RED}✗${NC}  ${DIM}CLI launcher${NC}"
        ! $HAS_VERSION  && say "  ${RED}✗${NC}  ${DIM}Version record${NC}"
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
    [[ -n "$APP_DIR" && "$APP_DIR" == "$HOME/Applications/ElyPrismLauncher" ]] \
        || fail "Unexpected APP_DIR value, aborting"
    step "Removing ElyPrismLauncher..."
    rm -rf "$APP_DIR" "$CLI_LAUNCHER" "$LOCAL_DESKTOP"
    ok "ElyPrismLauncher removed"
    exit 0
}

# ── Install functions ─────────────────────────────────────────
download_and_extract() {
    info "Downloading  ${DIM}($LATEST_VERSION  $ARCH)${NC}..."
    local tmp_tar="$APP_DIR/download.tar.gz.part"
    _PARTIAL="$tmp_tar"
    curl -L --progress-bar -o "$tmp_tar" "$LATEST_URL" \
        || fail "Failed to download archive"

    info "Extracting..."
    tar -xzf "$tmp_tar" -C "$APP_DIR" \
        || fail "Failed to extract archive"
    rm -f "$tmp_tar"
    _PARTIAL=""

    [[ -x "$LAUNCHER" ]] || fail "Expected launcher not found after extraction: $LAUNCHER"
    ok "Files extracted"
}

install_desktop() {
    mkdir -p "$(dirname "$LOCAL_DESKTOP")"
    cat > "$LOCAL_DESKTOP" <<EOF
[Desktop Entry]
Name=ElyPrismLauncher
Comment=Minecraft launcher with Ely.by account support
Exec=$SCRIPT_PATH --launch
Icon=$ICON
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=elyprismlauncher
StartupNotify=true
EOF
    ok "Desktop shortcut ready"
}

install_cli() {
    mkdir -p "$HOME/.local/bin"
    cat > "$CLI_LAUNCHER" <<EOF
#!/usr/bin/env bash
# ElyPrismLauncher CLI — launch detached then exit
exec "$SCRIPT_PATH" --launch
EOF
    chmod +x "$CLI_LAUNCHER"
    [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] \
        && warn "~/.local/bin is not in your PATH — add it to use 'elyprismlauncher' from terminal"
    ok "CLI launcher ready  ${DIM}(run: elyprismlauncher)${NC}"
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
                if $HAS_LAUNCHER && [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
                    SKIP_DOWNLOAD=true
                fi
                ;;
            3) do_remove ;;
            *) info "Bye!"; exit 0 ;;
        esac
        ;;
    full)
        menu "Reinstall ($INSTALLED_VERSION)" "Remove" "Exit"
        case "$PICK" in
            1) SKIP_DOWNLOAD=true ;;
            2) do_remove ;;
            *) info "Bye!"; exit 0 ;;
        esac
        ;;
esac

# ── Repair: only touch missing/broken pieces ──────────────────
if [[ "$INSTALL_STATE" == "partial" && "$PICK" == "1" ]]; then

    if $HAS_LAUNCHER; then skip "ElyPrismLauncher";  else download_and_extract; fi
    if $HAS_ICON;     then skip "Icon";            else warn "Icon missing — reinstall to restore it"; fi
    if $HAS_CLI;      then skip "CLI launcher";    else install_cli;          fi
    if $HAS_DESKTOP;  then skip "Desktop shortcut"; else install_desktop;     fi

    if $HAS_VERSION; then
        skip "Version record"
    else
        echo "$LATEST_VERSION" > "$VERSION_FILE"
        ok "Version record written"
    fi

    ok "Repair complete"

# ── Full clean install / reinstall ────────────────────────────
else

    [[ -n "$APP_DIR" && "$APP_DIR" == "$HOME/Applications/ElyPrismLauncher" ]] \
        || fail "Unexpected APP_DIR value, aborting"

    STASHED_DIR=""
    if $SKIP_DOWNLOAD && [[ -d "$APP_DIR" ]]; then
        STASHED_DIR="$(mktemp -d /tmp/ElyPrismLauncher.XXXXXX)"
        cp -a "$APP_DIR/." "$STASHED_DIR/"
    fi

    step "Removing old installation..."
    rm -rf "$APP_DIR" "$CLI_LAUNCHER" "$LOCAL_DESKTOP"
    mkdir -p "$APP_DIR"

    if $SKIP_DOWNLOAD && [[ -n "$STASHED_DIR" ]]; then
        info "Reusing existing files  ${DIM}($INSTALLED_VERSION)${NC}..."
        cp -a "$STASHED_DIR/." "$APP_DIR/"
        rm -rf "$STASHED_DIR"
        ok "Files ready"
    else
        download_and_extract
    fi

    install_desktop
    install_cli

    echo "$LATEST_VERSION" > "$VERSION_FILE"

fi

# ── Refresh desktop database ──────────────────────────────────
command -v update-desktop-database &>/dev/null \
    && update-desktop-database "$HOME/.local/share/applications" &>/dev/null || true

# ── Summary ───────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔════════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◆  ElyPrismLauncher Ready    ◆       ║${NC}"
say "${MAGENTA}${BOLD}╚════════════════════════════════════════╝${NC}"
say "  Version  : ${BOLD}$LATEST_VERSION${NC}"
say "  Arch     : ${BOLD}$ARCH${NC}"
say "  Install  : ${BOLD}~/Applications/ElyPrismLauncher/${NC}"
say "  Launcher : ${BOLD}~/Applications/ElyPrismLauncher/ElyPrismLauncher${NC}"
say "  Shortcut : ${BOLD}~/.local/share/applications/elyprismlauncher.desktop${NC}"
say "  CLI      : ${BOLD}~/.local/bin/elyprismlauncher${NC}"
say ""