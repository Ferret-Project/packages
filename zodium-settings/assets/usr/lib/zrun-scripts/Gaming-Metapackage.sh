#!/usr/bin/env bash
# ================================================================
#  Gaming-Meta — Flatpak Gaming Meta Installer
# ================================================================
# @tags: Applications

set -Eeuo pipefail

command -v flatpak &>/dev/null || { printf '%s\n' "⦻  flatpak is required" >&2; exit 1; }

# ── Styling ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'
DIM='\033[2m'; BLUE='\033[0;34m'

say()  { printf '%b\n' "$*"; }
ok()   { say "${GREEN}◆${NC}  $*"; }
warn() { say "${YELLOW}◇${NC}  $*"; }
fail() { say "${RED}⦻${NC}  $*" >&2; exit 1; }
step() { say "${BLUE}›${NC}  $*"; }

# ── Apps ──────────────────────────────────────────────────────
APP_NAMES=("Steam" "Heroic" "Lutris" "Bottles" "ProtonPlus" "ProtonUp-Qt" "MangoJuice" "Cartridges")
APP_IDS=(
    "com.valvesoftware.Steam"
    "com.heroicgameslauncher.hgl"
    "net.lutris.Lutris"
    "com.usebottles.bottles"
    "com.vysp3r.ProtonPlus"
    "net.davidotek.pupgui2"
    "io.github.radiolamp.mangojuice"
    "page.kramo.Cartridges"
)
n_total=${#APP_NAMES[@]}

# ── Flags ─────────────────────────────────────────────────────
SCOPE_FLAG=""   # --user | --system | "" (flatpak default)
NON_INTERACTIVE=false
ACTION=""       # install-missing | install-all | update-all | reinstall-all | remove-all | reset-all

usage() {
    say "Usage: ${0##*/} [options] [action]"
    say ""
    say "Options:"
    say "  ${CYAN}--user${NC}              operate on user installation"
    say "  ${CYAN}--system${NC}            operate on system installation"
    say "  ${CYAN}--yes${NC}               skip confirmation prompts"
    say ""
    say "Actions (non-interactive):"
    say "  ${CYAN}install-missing${NC}     install only apps not yet present"
    say "  ${CYAN}install-all${NC}         install all apps"
    say "  ${CYAN}update-all${NC}          update all installed apps"
    say "  ${CYAN}reinstall-all${NC}       remove and reinstall all (keeps data)"
    say "  ${CYAN}remove-all${NC}          remove all apps (keeps data)"
    say "  ${CYAN}reset-all${NC}           remove all apps and delete their data"
    say ""
    exit 0
}

while (( $# > 0 )); do
    case "$1" in
        --user)
            [[ "$SCOPE_FLAG" == "--system" ]] && fail "Cannot use --user and --system together"
            SCOPE_FLAG="--user" ;;
        --system)
            [[ "$SCOPE_FLAG" == "--user" ]] && fail "Cannot use --user and --system together"
            SCOPE_FLAG="--system" ;;
        --yes)     NON_INTERACTIVE=true ;;
        --help|-h) usage ;;
        install-missing|install-all|update-all|reinstall-all|remove-all|reset-all)
            ACTION="$1" ;;
        *) fail "Unknown option: $1  (try --help)" ;;
    esac
    shift
done

[[ -n "$ACTION" ]] && NON_INTERACTIVE=true

# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔═════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  Gaming Meta  ◈     ║${NC}"
say "${MAGENTA}${BOLD}╚═════════════════════════╝${NC}"
say ""
[[ -n "$SCOPE_FLAG" ]] && say "  ${DIM}scope: $SCOPE_FLAG${NC}\n"

# ── Flathub ───────────────────────────────────────────────────
has_flathub() {
    # shellcheck disable=SC2086
    flatpak $SCOPE_FLAG remote-list --columns=name 2>/dev/null | grep -qx 'flathub'
}

ensure_flathub() {
    has_flathub && return
    step "Adding Flathub..."
    # shellcheck disable=SC2086,SC2015
    flatpak $SCOPE_FLAG remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo \
        && ok "Flathub added" \
        || fail "Failed to add Flathub"
}

# ── Scan (single pass) ────────────────────────────────────────
mapfile -t _FLATPAK_INSTALLED < <(
    # shellcheck disable=SC2086
    flatpak $SCOPE_FLAG list --app --columns=application 2>/dev/null
)

is_installed() {
    local id=$1
    local entry
    for entry in "${_FLATPAK_INSTALLED[@]}"; do
        [[ "$entry" == "$id" ]] && return 0
    done
    return 1
}

IS_INSTALLED=()
n_installed=0
for i in "${!APP_IDS[@]}"; do
    if is_installed "${APP_IDS[$i]}"; then
        IS_INSTALLED+=("true")
        (( n_installed++ )) || true
    else
        IS_INSTALLED+=("false")
    fi
done

if   (( n_installed == 0 ));      then INSTALL_STATE="none"
elif (( n_installed == n_total )); then INSTALL_STATE="full"
else                                    INSTALL_STATE="partial"
fi

# ── Status ────────────────────────────────────────────────────
case "$INSTALL_STATE" in
    none)    warn "Nothing installed" ;;
    full)    ok   "All installed  ${DIM}($n_installed/$n_total)${NC}" ;;
    partial) warn "Partial  ${DIM}($n_installed/$n_total)${NC}" ;;
esac
has_flathub || say "  ${RED}✗${NC}  ${DIM}Flathub${NC}"
for i in "${!APP_NAMES[@]}"; do
    if [[ "${IS_INSTALLED[$i]}" == "true" ]]; then
        say "  ${GREEN}◆${NC}  ${DIM}${APP_NAMES[$i]}${NC}"
    else
        say "  ${RED}✗${NC}  ${DIM}${APP_NAMES[$i]}${NC}"
    fi
done
say ""

# ── Helpers ───────────────────────────────────────────────────
confirm() {
    local prompt=${1:-"Continue?"}
    $NON_INTERACTIVE && return 0
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

# ── Action functions ──────────────────────────────────────────

# Uninstall apps currently marked installed.
# $1 = true → --delete-data; false → keep data.
# Returns 1 if any removal failed, 0 if all succeeded.
_remove_installed() {
    local delete_data=${1:-false}
    local flag="" failed=0
    $delete_data && flag="--delete-data"
    for i in "${!APP_NAMES[@]}"; do
        [[ "${IS_INSTALLED[$i]}" != "true" ]] && continue
        # shellcheck disable=SC2086
        if ! flatpak uninstall -y $flag $SCOPE_FLAG "${APP_IDS[$i]}" >/dev/null; then
            warn "Failed to remove ${APP_NAMES[$i]}"
            failed=1
        fi
    done
    return "$failed"
}

do_install_missing() {
    ensure_flathub
    local ids=()
    for i in "${!APP_IDS[@]}"; do
        [[ "${IS_INSTALLED[$i]}" == "false" ]] && ids+=("${APP_IDS[$i]}")
    done
    (( ${#ids[@]} == 0 )) && { ok "Nothing to install"; return; }
    step "Installing ${#ids[@]} missing app(s)..."
    # shellcheck disable=SC2086
    if flatpak install -y $SCOPE_FLAG flathub "${ids[@]}"; then ok "Done"; else warn "Some installs failed"; fi
}

do_install_all() {
    ensure_flathub
    step "Installing all $n_total apps..."
    # shellcheck disable=SC2086
    if flatpak install -y $SCOPE_FLAG flathub "${APP_IDS[@]}"; then ok "Done"; else warn "Some installs failed"; fi
}

do_update_all() {
    local ids=()
    for i in "${!APP_IDS[@]}"; do
        [[ "${IS_INSTALLED[$i]}" == "true" ]] && ids+=("${APP_IDS[$i]}")
    done
    (( ${#ids[@]} == 0 )) && { ok "Nothing to update"; return; }
    step "Updating ${#ids[@]} app(s)..."
    # shellcheck disable=SC2086
    if flatpak update -y $SCOPE_FLAG "${ids[@]}"; then ok "Done"; else warn "Some updates failed"; fi
}

do_reinstall_all() {
    ensure_flathub
    confirm "${YELLOW}Reinstall all apps? App data will be kept.${NC}" || { ok "Cancelled"; exit 0; }
    step "Removing apps..."
    _remove_installed false || warn "Some removals failed"
    step "Installing all $n_total apps..."
    # shellcheck disable=SC2086
    if flatpak install -y $SCOPE_FLAG flathub "${APP_IDS[@]}"; then ok "Done"; else warn "Some installs failed"; fi
}

do_remove_all() {
    confirm "${YELLOW}Remove all gaming apps? App data will be kept.${NC}" || { ok "Cancelled"; exit 0; }
    step "Removing apps..."
    if _remove_installed false; then ok "Removed"; else warn "Some removals failed"; fi
}

do_reset_all() {
    confirm "${RED}Remove all apps AND delete their data? This cannot be undone.${NC}" || { ok "Cancelled"; exit 0; }
    step "Removing apps and deleting data..."
    if _remove_installed true; then ok "Removed"; else warn "Some removals failed"; fi
}

# ── Dispatch ──────────────────────────────────────────────────
if [[ -n "$ACTION" ]]; then
    case "$ACTION" in
        install-missing) do_install_missing ;;
        install-all)     do_install_all ;;
        update-all)      do_update_all ;;
        reinstall-all)   do_reinstall_all ;;
        remove-all)      do_remove_all; exit 0 ;;
        reset-all)       do_reset_all;  exit 0 ;;
    esac
else
    PICK=""
    case "$INSTALL_STATE" in
        none)
            menu "Install all" "Exit"
            case "$PICK" in
                1) do_install_all ;;
                *) ok "Bye!"; exit 0 ;;
            esac
            ;;
        partial)
            menu "Install missing" "Install all" "Remove all (keep data)" "Reset all (delete app data)" "Exit"
            case "$PICK" in
                1) do_install_missing ;;
                2) do_install_all ;;
                3) do_remove_all; exit 0 ;;
                4) do_reset_all;  exit 0 ;;
                *) ok "Bye!"; exit 0 ;;
            esac
            ;;
        full)
            menu "Update all" "Reinstall all (keep data)" "Remove all (keep data)" "Reset all (delete app data)" "Exit"
            case "$PICK" in
                1) do_update_all ;;
                2) do_reinstall_all ;;
                3) do_remove_all; exit 0 ;;
                4) do_reset_all;  exit 0 ;;
                *) ok "Bye!"; exit 0 ;;
            esac
            ;;
    esac
fi

# ── Summary ───────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◆  Gaming Meta — Done    ║${NC}"
say "${MAGENTA}${BOLD}╚════════════════════════════╝${NC}"
say ""