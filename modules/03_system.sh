#!/usr/bin/env bash
#
# modules/03_system.sh
# Phase 3 - Clear stale systemd-managed temporary files and vacuum
# journald logs down to a fixed retention window.
#

log "Phase 3: System cleanup..."

if command -v systemd-tmpfiles >/dev/null 2>&1; then
    run_cmd sudo systemd-tmpfiles --clean --remove
else
    log "systemd-tmpfiles not found; skipping tmpfiles cleanup."
fi

run_cmd sudo journalctl --vacuum-time="${JOURNAL_RETENTION:-7d}"