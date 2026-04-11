#!/usr/bin/env bash
# ================================================================
#  Group Setup — add/remove users from groups
#  rpm-ostree / bootc workaround for /etc/group population
# ================================================================
# @tags: System

set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'
DIM='\033[2m'; BLUE='\033[0;34m'

say()  { printf '%b\n' "$*"; }
ok()   { say "${GREEN}✔${NC} $*"; }
warn() { say "${YELLOW}!${NC} $*"; }
fail() { say "${RED}✘${NC} $*" >&2; exit 1; }
step() { say "${BLUE}→${NC} $*"; }
dim()  { say "${DIM}  $*${NC}"; }

confirm() {
    printf '%b' "$1 ${DIM}[y/N]${NC} "
    read -r _ans
    [[ "$_ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

group_in_lib() { grep -qE "^$1:" /usr/lib/group 2>/dev/null; }
group_in_etc() { grep -qE "^$1:" /etc/group     2>/dev/null; }
user_exists()  { id "$1" &>/dev/null; }
user_in_group(){ id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }

# ── Header ────────────────────────────────────────────────────
say "${MAGENTA}${BOLD}╔═════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  User Groups Manager  ◈     ║${NC}"
say "${MAGENTA}${BOLD}╚═════════════════════════════════╝${NC}"

# ── User ──────────────────────────────────────────────────────
DEFAULT_USER="${SUDO_USER:-$USER}"
REAL_USERS=()
while IFS= read -r u; do REAL_USERS+=("$u"); done \
    < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)

if [[ ${#REAL_USERS[@]} -eq 1 ]]; then
    TARGET_USER="${REAL_USERS[0]}"
    say "${CYAN}▸${NC} user ${BOLD}${TARGET_USER}${NC} ${DIM}(auto)${NC}"
else
    printf '%b' "${CYAN}▸${NC} user ${DIM}[${DEFAULT_USER}]${NC}: "
    read -r INPUT_USER
    TARGET_USER="${INPUT_USER:-$DEFAULT_USER}"
fi
user_exists "$TARGET_USER" || fail "user '${TARGET_USER}' not found"

# ── Action — a/r prompt ───────────────────────────────────────
printf '%b' "${CYAN}▸${NC} action ${DIM}[A/r]${NC} ${DIM}(A=add r=remove)${NC}: "
read -r ACTION_INPUT
case "${ACTION_INPUT,,}" in
    r|remove) ACTION="remove" ;;
    *)        ACTION="add"    ;;
esac
say "${BLUE}→${NC} ${BOLD}${ACTION}${NC}"

# ── Remove flow ───────────────────────────────────────────────
if [[ "$ACTION" == "remove" ]]; then
    say "${CYAN}▸${NC} groups of ${BOLD}${TARGET_USER}${NC}:"
    CURRENT_GROUPS=()
    while IFS= read -r g; do
        [[ -z "$g" ]] && continue
        CURRENT_GROUPS+=("$g")
        printf '%b' "  ${GREEN}✔${NC} ${CYAN}${BOLD}${g}${NC}  "
    done < <(id -nG "$TARGET_USER" | tr ' ' '\n' | sort)
    say ""
    [[ ${#CURRENT_GROUPS[@]} -eq 0 ]] && fail "${TARGET_USER} has no groups"

    printf '%b' "${CYAN}▸${NC} remove from ${DIM}(space/comma)${NC}: "
    read -r GROUP_INPUT
    [[ -z "$GROUP_INPUT" ]] && fail "no groups entered"
    IFS=' ,' read -ra RAW_GROUPS <<< "$GROUP_INPUT"

    VALID_GROUPS=()
    for g in "${RAW_GROUPS[@]}"; do
        [[ -z "$g" ]] && continue
        if user_in_group "$TARGET_USER" "$g"; then
            VALID_GROUPS+=("$g")
            say "  ${GREEN}✔${NC} ${BOLD}${CYAN}${g}${NC} ${DIM}→ queued${NC}"
        else
            say "  ${RED}✘${NC} ${BOLD}${g}${NC} ${DIM}→ not a member${NC}"
        fi
    done
    [[ ${#VALID_GROUPS[@]} -eq 0 ]] && fail "nothing to remove"

    confirm "${YELLOW}!${NC} remove ${BOLD}${TARGET_USER}${NC} from ${CYAN}${BOLD}${VALID_GROUPS[*]}${NC}?" \
        || { ok "cancelled"; exit 0; }

    for g in "${VALID_GROUPS[@]}"; do
        step "${TARGET_USER} ← ${BOLD}${g}${NC}"
        sudo gpasswd -d "$TARGET_USER" "$g" \
            && ok "removed from ${BOLD}${g}${NC}" \
            || warn "failed — ${g}"
    done

# ── Add flow ──────────────────────────────────────────────────
else
    printf '%b' "${CYAN}▸${NC} groups ${DIM}(usermod)${NC}: "
    read -r GROUP_INPUT
    [[ -z "$GROUP_INPUT" ]] && fail "no groups entered"
    IFS=' ,' read -ra RAW_GROUPS <<< "$GROUP_INPUT"

    VALID_GROUPS=()
    NEEDS_POPULATE=()

    for g in "${RAW_GROUPS[@]}"; do
        [[ -z "$g" ]] && continue
        if group_in_etc "$g"; then
            SRC="${GREEN}etc${NC}"
        elif group_in_lib "$g"; then
            SRC="${YELLOW}lib*${NC}"
            NEEDS_POPULATE+=("$g")
        else
            say "  ${RED}✘${NC} ${BOLD}${g}${NC} ${DIM}→ not found${NC}"
            continue
        fi
        if user_in_group "$TARGET_USER" "$g"; then
            MEM="${GREEN}member${NC}"
        else
            MEM="${YELLOW}not member${NC}"
        fi
        say "  ${BLUE}→${NC} ${BOLD}${CYAN}${g}${NC} ${DIM}[${NC}${SRC}${DIM}]${NC} ${DIM}·${NC} ${MEM}"
        VALID_GROUPS+=("$g")
    done

    [[ ${#VALID_GROUPS[@]} -eq 0 ]] && fail "no valid groups found"
    [[ ${#NEEDS_POPULATE[@]} -gt 0 ]] && \
        dim "* will populate from /usr/lib/group: ${NEEDS_POPULATE[*]}"

    confirm "${YELLOW}!${NC} add ${BOLD}${TARGET_USER}${NC} to ${CYAN}${BOLD}${VALID_GROUPS[*]}${NC}?" \
        || { ok "cancelled"; exit 0; }

    for g in "${VALID_GROUPS[@]}"; do
        if user_in_group "$TARGET_USER" "$g"; then
            dim "${g} → already member, skipping"
            continue
        fi
        if ! group_in_etc "$g" && group_in_lib "$g"; then
            step "populating ${BOLD}${g}${NC} → /etc/group"
            grep -E "^${g}:" /usr/lib/group | sudo tee -a /etc/group > /dev/null
        fi
        step "${TARGET_USER} → ${BOLD}${g}${NC}"
        sudo usermod -aG "$g" "$TARGET_USER" \
            && ok "added to ${BOLD}${g}${NC}" \
            || warn "failed — ${g}"
    done
fi

# ── Done ──────────────────────────────────────────────────────
say "${MAGENTA}${BOLD}╔════════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◆  User Group Management Complete     ║${NC}"
say "${MAGENTA}${BOLD}╚════════════════════════════════════════╝${NC}"
ok "done · log out and back in to apply"
dim "verify: id ${TARGET_USER}"
say ""