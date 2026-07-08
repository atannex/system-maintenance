#!/usr/bin/env bash
#
# lib/helpers.sh
# Shared logging, execution, and system-inspection helpers for the
# system-maintenance toolkit. This file is meant to be sourced, not
# executed directly.
#

LOGFILE="${LOGFILE:-${HOME}/system-maintenance.log}"
CONFIG_FILE="${CONFIG_FILE:-${HOME}/.config/system-maintenance.conf}"

# --- Logging ----------------------------------------------------------------
# All three log functions write a timestamped line to both the console and
# the log file. warn()/error() correctly send console output to stderr while
# still capturing the same line in the log file (the original implementation
# piped stderr into tee *after* redirecting it away, so nothing reached the
# log).

_timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
    printf '[%s] INFO: %s\n' "$(_timestamp)" "$*" | tee -a "$LOGFILE"
}

warn() {
    printf '[%s] WARN: %s\n' "$(_timestamp)" "$*" | tee -a "$LOGFILE" >&2
}

error() {
    printf '[%s] ERROR: %s\n' "$(_timestamp)" "$*" | tee -a "$LOGFILE" >&2
}

# --- Command execution -------------------------------------------------------
# Runs a command, honoring DRY_RUN, and reports (rather than silently
# swallowing) any failure. Returns the underlying command's exit status so
# callers using `&&`/`||` or checking `$?` behave correctly.
run_cmd() {
    log "Running: $*"

    if [[ "${DRY_RUN:-false}" == true ]]; then
        echo "[DRY-RUN] Would execute: $*"
        return 0
    fi

    if "$@"; then
        return 0
    else
        local status=$?
        error "Command failed (exit ${status}): $*"
        return "$status"
    fi
}

# --- System inspection --------------------------------------------------------
get_disk_usage() {
    df -h / | awk 'NR==2 {print $4}'
}

# Returns 0 (true) if the system requires a reboot, 1 otherwise.
needs_reboot() {
    if [[ -f /var/run/reboot-required ]]; then
        return 0
    fi

    if command -v needrestart >/dev/null 2>&1; then
        # -b (batch mode) prints machine-readable NEEDRESTART-* lines; a
        # NEEDRESTART-KSTA value other than 1 means the running kernel
        # differs from the installed one, i.e. a reboot is warranted.
        if sudo needrestart -b 2>/dev/null | grep -qE '^NEEDRESTART-KSTA:\s*[^1]'; then
            return 0
        fi
    fi

    return 1
}