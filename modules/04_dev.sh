#!/usr/bin/env bash
#
# modules/04_dev.sh
# Phase 4 - Clean development-tool caches. Docker is handled today;
# add further caches (e.g. npm, pip, cargo) below following the same
# pattern.
#

log "Phase 4: Dev environment cleanup..."

if command -v docker >/dev/null 2>&1; then
    if [[ "${AGGRESSIVE_CLEAN:-false}" == true ]]; then
        warn "Aggressive mode: pruning all unused Docker data, including volumes."
        run_cmd docker system prune -a -f --volumes
    else
        run_cmd docker system prune -a -f
    fi
else
    log "Docker not found; skipping Docker cleanup."
fi

# Add other dev caches here, e.g.:
# command -v npm >/dev/null 2>&1 && run_cmd npm cache clean --force
# command -v pip >/dev/null 2>&1 && run_cmd pip cache purge