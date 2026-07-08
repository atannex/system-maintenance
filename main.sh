#!/usr/bin/env bash
#
# maintenance.sh
# Orchestrates routine system maintenance: package updates, cache and
# journal cleanup, developer-tool cache pruning, and a reboot check.
#
# Usage:
#   ./maintenance.sh [options]
#
# Options:
#   -n, --dry-run      Print what would be done without making changes.
#   -v, --verbose       Enable verbose shell tracing.
#       --auto-reboot   Reboot automatically if the system requires it.
#       --aggressive    Also prune unused Docker volumes in phase 4.
#   -h, --help          Show this help message and exit.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Defaults ----------------------------------------------------------------
DRY_RUN=false
VERBOSE=false
AUTO_REBOOT=false
AGGRESSIVE_CLEAN=false

usage() {
    sed -n '2,/^set -Eeuo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | head -n -1
}

# --- Argument parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)     DRY_RUN=true ;;
        -v|--verbose)     VERBOSE=true ;;
        --auto-reboot)    AUTO_REBOOT=true ;;
        --aggressive)     AGGRESSIVE_CLEAN=true ;;
        -h|--help)        usage; exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

[[ "$VERBOSE" == true ]] && set -x

# --- Load helpers and config ---------------------------------------------------
# shellcheck source=lib/helpers.sh
source "./lib/helpers.sh"

if [[ -f "$CONFIG_FILE" ]]; then
    # The config file is sourced as shell, so it can override any variable
    # above. Only trust it if it's owned by the current user and not
    # writable by group or others.
    perms="$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null)"
    if [[ -O "$CONFIG_FILE" ]] && [[ "${perms: -2}" =~ ^[0-4][0-4]$ ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        warn "Ignoring ${CONFIG_FILE}: unsafe ownership or permissions (expected owner-only, e.g. chmod 600)."
    fi
fi

# --- Error handling ------------------------------------------------------------
on_error() {
    local exit_code=$?
    error "Maintenance aborted (exit ${exit_code}) at line ${BASH_LINENO[0]}."
    exit "$exit_code"
}
trap on_error ERR

# --- Run ------------------------------------------------------------------------
log "=== Maintenance Started (dry-run=${DRY_RUN}, auto-reboot=${AUTO_REBOOT}, aggressive=${AGGRESSIVE_CLEAN}) ==="
INITIAL_SPACE=$(get_disk_usage)

# shellcheck source=modules/01_update.sh
source "./modules/01_update.sh"
# shellcheck source=modules/02_cleanup.sh
source "./modules/02_cleanup.sh"
# shellcheck source=modules/03_system.sh
source "./modules/03_system.sh"
# shellcheck source=modules/04_dev.sh
source "./modules/04_dev.sh"
# shellcheck source=modules/05_health.sh
source "./modules/05_health.sh"

log "=== Maintenance Complete. Initial free space: ${INITIAL_SPACE} | Final: $(get_disk_usage) ==="