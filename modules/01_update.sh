#!/usr/bin/env bash
#
# modules/01_update.sh
# Phase 1 - Update APT package lists, upgrade installed packages, and
# refresh firmware where fwupdmgr is available.
#
# Expected to be sourced by maintenance.sh, which provides log(), run_cmd(),
# and DRY_RUN.
#

log "Phase 1: Updating packages..."

run_cmd sudo apt-get update
run_cmd sudo apt-get full-upgrade -y

if command -v fwupdmgr >/dev/null 2>&1; then
    run_cmd sudo fwupdmgr refresh --force
    run_cmd sudo fwupdmgr update -y
else
    log "fwupdmgr not found; skipping firmware updates."
fi