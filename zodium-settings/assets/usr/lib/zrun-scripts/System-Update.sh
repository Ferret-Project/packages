#!/usr/bin/env bash
# ================================================================
#  Update-System — Updates system using zync (core updates only)
# ================================================================
# @tags: General

set -Eeuo pipefail

# ── Styling ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

say()  { printf "$@"; printf '\n'; }
info() { say "${CYAN}◈${NC}  $*"; }
ok()   { say "${GREEN}◆${NC}  $*"; }
fail() { say "${RED}⦻${NC}  $*" >&2; exit 1; }

# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  System Update  ◈      ║${NC}"
say "${MAGENTA}${BOLD}╚════════════════════════════╝${NC}"
say ""

# ── Run zync update ───────────────────────────────────────────
info "Running system update using zync..."
/usr/bin/zync --system --flatpak --firmware --brew || fail "zync update failed."
ok "System update completed successfully."