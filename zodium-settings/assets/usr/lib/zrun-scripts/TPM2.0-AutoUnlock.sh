#!/usr/bin/env bash
# ================================================================
#  tpm2-auto-unlock-luks2 — Setup TPM2 auto decryption for LUKS2
#  Interactive, works on Fedora, Fedora Atomic, ublue images
#  Made for Zodium Project
# ================================================================
# @tags: General

set -Eeuo pipefail

# ── Styling ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

say()  { printf "$@"; printf '\n'; }
info() { say "${CYAN}◈${NC}  $*"; }
ok()   { say "${GREEN}◆${NC}  $*"; }
warn() { say "${YELLOW}◇${NC}  $*"; }
fail() { say "${RED}⦻${NC}  $*" >&2; exit 1; }

# ── Header ────────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔══════════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◈  TPM2 LUKS2 Auto-Unlock Setup  ◈     ║${NC}"
say "${MAGENTA}${BOLD}╚══════════════════════════════════════════╝${NC}"
say ""

# ── Root check ────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    warn "This script requires root — re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# ── TPM2 check ────────────────────────────────────────────────
if [[ -f /sys/class/tpm/tpm0/device/description ]]; then
    info "TPM device detected: $(< /sys/class/tpm/tpm0/device/description)"
else
    fail "No TPM2 device detected."
fi

systemd-analyze has-tpm2 &>/dev/null || fail "Systemd TPM2 support not available."
ok "Systemd TPM2 support detected"

# ── Detect LUKS2 root device ──────────────────────────────────
info "Detecting LUKS2 root device from kernel parameters..."

RD_LUKS_UUID="$(xargs -n1 -a /proc/cmdline \
    | grep -F 'rd.luks.uuid=' \
    | cut -d= -f2 \
    | sed 's/^luks-//' || true)"

if [[ -z "${RD_LUKS_UUID:-}" ]]; then
    warn "No LUKS root detected in kernel parameters."
    warn "Your root filesystem does not appear to be LUKS-encrypted."
    fail "Cannot enroll TPM2 auto-unlock without a LUKS2 root device."
fi

CRYPT_DISK="$(realpath "/dev/disk/by-uuid/${RD_LUKS_UUID}")"

if ! find /dev -iname "${RD_LUKS_UUID:-INVALID}" \
    | grep -F "${RD_LUKS_UUID}" &>/dev/null; then
    fail "Could not find LUKS device used to boot system."
fi

ok "Detected root device: ${BOLD}${CRYPT_DISK}${NC}"

# ── Enable / Disable ──────────────────────────────────────────
say ""
read -rp "  Enable TPM2 auto-unlock? [y/N]: " ENABLE

if [[ "${ENABLE,,}" == "n" || -z "$ENABLE" ]]; then
    info "Disabling TPM2 auto-unlock (wiping TPM2 slot)..."
    systemd-cryptenroll --wipe-slot=tpm2 "${CRYPT_DISK}"
    ok "TPM2 auto-unlock disabled"
    exit 0
fi

# ── Optional PIN ──────────────────────────────────────────────
say ""
read -rp "  Set up a TPM2 PIN? [y/N]: " USE_PIN

PIN_ENABLED="No"
ENROLL_ARGS=()
if [[ "${USE_PIN,,}" == "y" ]]; then
    ENROLL_ARGS+=("--tpm2-with-pin=yes")
    PIN_ENABLED="Yes"
fi

# ── PCR selection ─────────────────────────────────────────────
read -rp "  PCRs to bind TPM2 key [default: 7]: " PCR_INPUT
PCRS="${PCR_INPUT:-7}"

# ── Enroll ────────────────────────────────────────────────────
say ""
info "Enrolling TPM2 key..."
systemd-cryptenroll \
    --wipe-slot=tpm2 \
    --tpm2-device=auto \
    --tpm2-pcrs="${PCRS}" \
    "${ENROLL_ARGS[@]}" \
    "${CRYPT_DISK}"

ok "TPM2 auto-unlock configured for next reboot."

# ── Summary ───────────────────────────────────────────────────
say ""
say "${MAGENTA}${BOLD}╔═════════════════════════════════════╗${NC}"
say "${MAGENTA}${BOLD}║   ◆  TPM2 Auto-Unlock Configured    ║${NC}"
say "${MAGENTA}${BOLD}╚═════════════════════════════════════╝${NC}"
say "  Device      : ${BOLD}${CRYPT_DISK}${NC}"
say "  PCRs used   : ${BOLD}${PCRS}${NC}"
say "  PIN enabled : ${BOLD}${PIN_ENABLED}${NC}"
say ""
say "  ${YELLOW}◇${NC}  Reboot to verify. Fallback passphrase remains available."
say ""