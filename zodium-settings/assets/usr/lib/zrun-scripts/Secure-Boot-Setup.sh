#!/usr/bin/env bash
# ================================================================
#  enroll-secure-boot-key — MOK Enrollment Script
#  Automatically adds a MOK key to Secure Boot pending list
# ================================================================
# @tags: General

set -Eeuo pipefail

# ── Dependency check ──────────────────────────────────────────
command -v mokutil &>/dev/null || { echo "⦻  mokutil is required but not installed" >&2; exit 1; }

# ── Styling ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

say()  { printf "$@"; printf '\n'; }
info() { say "${CYAN}◈${NC}  $*"; }
ok()   { say "${GREEN}◆${NC}  $*"; }
warn() { say "${YELLOW}◇${NC}  $*"; }
fail() { say "${RED}⦻${NC}  $*" >&2; exit 1; }

# ── Config ────────────────────────────────────────────────────
ENROLLMENT_PASSWORD="zodium"
ENROLLMENT_MOK_DER="/etc/pki/akmods/certs/zodium-mok.der"

# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔════════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  Secure Boot MOK Enrollment  ◈     ║${NC}"
say "${MAGENTA}${BOLD}╚════════════════════════════════════════╝${NC}"
say ""

# ── Check MOK file ────────────────────────────────────────────
sudo test -f "$ENROLLMENT_MOK_DER" || fail "MOK file not found at $ENROLLMENT_MOK_DER"
ok "MOK file found → $ENROLLMENT_MOK_DER"

# ── Enrollment ────────────────────────────────────────────────
info "Starting MOK enrollment..."

OUTPUT=$(printf '%s\n%s\n' "$ENROLLMENT_PASSWORD" "$ENROLLMENT_PASSWORD" \
    | sudo mokutil --import "$ENROLLMENT_MOK_DER" 2>&1) || true

if [[ "$OUTPUT" == *"SKIP:"* ]]; then
    warn "Key is already pending enrollment — no changes made"
else
    ok "MOK enrollment request added"
fi

# ── Next steps ────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔═══════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◆  Enrollment Queued    ║${NC}"
say "${MAGENTA}${BOLD}╚═══════════════════════════╝${NC}"
say ""
say "  ${CYAN}◈${NC}  Next steps:"
say ""
say "  ${BOLD}1)${NC} Reboot your system"
say "  ${BOLD}2)${NC} When the MOK menu appears, select ${BOLD}Enroll MOK${NC}"
say "  ${BOLD}3)${NC} Enter the password: ${BOLD}$ENROLLMENT_PASSWORD${NC}"
say "  ${BOLD}4)${NC} Confirm and reboot"
say ""