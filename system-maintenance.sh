#!/usr/bin/env bash
# ==============================================================================
# Script Name:    system-maintenance.sh
# Version:        3.0.0
# Description:    Comprehensive, production-grade Linux maintenance for
#                 Debian/Ubuntu-based systems. Supports dry-run, logging,
#                 reboot detection, firmware updates, and more.
# ==============================================================================

set -Eeuo pipefail

# ----------------------------- Configuration -----------------------------
export APT_CONFIG=/dev/null
LOGFILE="${HOME}/system-maintenance.log"
DRY_RUN=false
VERBOSE=false
AUTO_REBOOT=false
AGGRESSIVE_CLEAN=false
CONFIG_FILE="${HOME}/.config/system-maintenance.conf"

# ----------------------------- Helpers -----------------------------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"
    echo "$msg" | tee -a "$LOGFILE" 2>/dev/null || echo "$msg"
}

warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*"
    echo "$msg" >&2 | tee -a "$LOGFILE" 2>/dev/null || echo "$msg" >&2
}

error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg" >&2 | tee -a "$LOGFILE" 2>/dev/null || echo "$msg" >&2
}

run_cmd() {
    log "Running: $*"
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would execute: $*"
        return 0
    fi
    "$@"
}

get_disk_usage() {
    df -h / | awk 'NR==2 {print $4}'
}

needs_reboot() {
    if [[ -f /var/run/reboot-required ]]; then
        return 0
    fi
    if command -v needrestart >/dev/null 2>&1; then
        if sudo needrestart -b 2>/dev/null | grep -q "Reboot"; then
            return 0
        fi
    fi
    return 1
}

# ----------------------------- Argument Parsing -----------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --auto-reboot) AUTO_REBOOT=true; shift ;;
        --aggressive) AGGRESSIVE_CLEAN=true; shift ;;
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]
Options:
  --dry-run, -n      Simulate without making changes
  --verbose, -v      Verbose output
  --auto-reboot      Automatically reboot if required (use with caution)
  --aggressive       Enable more aggressive cleanup
  --help, -h         Show this help
EOF
            exit 0
            ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

# Load config if exists
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# ----------------------------- Safety Checks -----------------------------
if [[ "$EUID" -eq 0 ]]; then
    error "Do not run as root. Execute as normal user with sudo privileges."
    exit 1
fi

# ----------------------------- Initialization -----------------------------
INITIAL_SPACE=$(get_disk_usage)
log "=== System Maintenance v3.0 Started ==="
log "Initial free space: ${INITIAL_SPACE}"
log "Dry run: ${DRY_RUN} | Aggressive: ${AGGRESSIVE_CLEAN} | Auto-reboot: ${AUTO_REBOOT}"

trap 'error "Unexpected error at line ${LINENO}. Check ${LOGFILE}"; exit 1' ERR

# ----------------------------- 1. Update Everything -----------------------------
log "Phase 1: Updating package managers and system..."

run_cmd sudo apt update
run_cmd sudo apt full-upgrade -y

if command -v aptitude >/dev/null 2>&1; then
    run_cmd sudo aptitude safe-upgrade -y
fi

# Install essential tools if missing
for pkg in default-jdk build-essential curl wget fwupd needrestart; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        log "Installing essential package: ${pkg}"
        run_cmd sudo apt install -y "$pkg"
    fi
done

# Firmware updates (fwupd)
if command -v fwupdmgr >/dev/null 2>&1; then
    log "Refreshing and applying firmware updates..."
    run_cmd sudo fwupdmgr refresh --force
    run_cmd sudo fwupdmgr update -y || true
fi

# Homebrew
if command -v brew >/dev/null 2>&1; then
    run_cmd brew update
    run_cmd brew upgrade
fi

# Flatpak
if command -v flatpak >/dev/null 2>&1; then
    run_cmd flatpak update -y
fi

# Snap
if command -v snap >/dev/null 2>&1; then
    run_cmd sudo snap refresh
fi

# Nix (if installed)
if command -v nix >/dev/null 2>&1; then
    log "Updating Nix packages..."
    run_cmd nix-channel --update || true
    run_cmd nix-env -u || true
fi

# ----------------------------- 2. Cleanup -----------------------------
log "Phase 2: Package cleanup and orphans..."

run_cmd sudo apt autoremove -y
run_cmd sudo apt autoclean

if command -v aptitude >/dev/null 2>&1; then
    run_cmd sudo aptitude clean
fi

if command -v brew >/dev/null 2>&1; then
    run_cmd brew cleanup --prune=all
    rm -rf "$(brew --cache)" 2>/dev/null || true
fi

if command -v flatpak >/dev/null 2>&1; then
    run_cmd flatpak uninstall --unused -y
fi

if command -v snap >/dev/null 2>&1; then
    log "Removing old Snap revisions..."
    set +e
    LANG=C snap list --all | awk '/disabled/{print $1,$3}' | while read -r s r; do
        sudo snap remove "$s" --revision="$r" || true
    done
    set -e
fi

# ----------------------------- 3. System Temp & Logs -----------------------------
log "Phase 3: System temporary files and logs..."

if command -v systemd-tmpfiles >/dev/null 2>&1; then
    run_cmd sudo systemd-tmpfiles --clean --remove
fi

# Safer temp cleanup
if [[ "$DRY_RUN" == false ]]; then
    sudo find /tmp -mindepth 1 -type f -mtime +2 -delete 2>/dev/null || true
    sudo find /var/tmp -mindepth 1 -type f -mtime +2 -delete 2>/dev/null || true
fi

if command -v journalctl >/dev/null 2>&1; then
    run_cmd sudo journalctl --vacuum-time=7d --vacuum-size=500M
fi

# ----------------------------- 4. User & Dev Caches -----------------------------
log "Phase 4: User and development caches..."

[[ -d "${HOME}/.cache" ]] && find "${HOME}/.cache" -mindepth 1 -delete 2>/dev/null || true

rm -rf \
    "${HOME}/.npm/_cacache" \
    "${HOME}/.composer/cache" \
    "${HOME}/.pip/cache" \
    "${HOME}/.cargo/registry/cache" \
    "${HOME}/.cargo/git/db" \
    "${HOME}/.m2/repository" \
    "${HOME}/.gradle/caches" \
    "${HOME}/.yarn/cache" \
    "${HOME}/.pnpm-store" \
    "${HOME}/.gem/cache" 2>/dev/null || true

# Language-specific
command -v pip >/dev/null && pip cache purge 2>/dev/null || true
command -v npm >/dev/null && npm cache clean --force 2>/dev/null || true
command -v rustup >/dev/null && rustup update 2>/dev/null || true

# Aggressive mode
if [[ "$AGGRESSIVE_CLEAN" == true ]]; then
    log "Aggressive cleanup enabled..."
    rm -rf "${HOME}/.cache/*" 2>/dev/null || true
fi

# ----------------------------- 5. Containers & Virtualization -----------------------------
if command -v docker >/dev/null 2>&1; then
    log "Pruning Docker..."
    run_cmd docker system prune -a --volumes -f
fi

if command -v podman >/dev/null 2>&1; then
    log "Pruning Podman..."
    run_cmd podman system prune -a -f
    run_cmd podman builder prune -a -f
fi

# ----------------------------- 6. Health Checks -----------------------------
log "Phase 6: System health checks..."

if command -v needrestart >/dev/null 2>&1; then
    sudo needrestart -b || true
fi

# Disk health (if smartmontools installed)
if command -v smartctl >/dev/null 2>&1; then
    log "Running quick disk health check..."
    sudo smartctl -H /dev/sda 2>/dev/null || true
fi

# ----------------------------- Final Report -----------------------------
FINAL_SPACE=$(get_disk_usage)
log "=== Maintenance Completed Successfully ==="
log "Free space before: ${INITIAL_SPACE} | After: ${FINAL_SPACE}"
log "Log: ${LOGFILE}"

if needs_reboot; then
    warn "=== REBOOT REQUIRED ==="
    if [[ "$AUTO_REBOOT" == true ]]; then
        log "Auto-rebooting in 30 seconds..."
        sleep 30
        sudo reboot
    else
        echo "Please reboot your system at your earliest convenience."
    fi
fi

if [[ "$VERBOSE" == true ]]; then
    echo "Maintenance finished. Disk space: ${FINAL_SPACE}"
fi