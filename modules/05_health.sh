#!/usr/bin/env bash
#
# modules/05_health.sh
# Phase 5 - Check whether a reboot is required and, if authorized,
# perform it.
#

log "Phase 5: Health checks..."

if needs_reboot; then
    warn "REBOOT REQUIRED"
    if [[ "${AUTO_REBOOT:-false}" == true ]]; then
        warn "AUTO_REBOOT is enabled; rebooting now."
        run_cmd sudo reboot
    else
        log "AUTO_REBOOT is disabled; skipping automatic reboot. Reboot manually at your convenience."
    fi
else
    log "No reboot required."
fi