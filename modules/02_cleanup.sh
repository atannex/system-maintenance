#!/usr/bin/env bash
#
# modules/02_cleanup.sh
# Phase 2 - Remove packages that are no longer required and clear the
# local APT package cache.
#

log "Phase 2: Cleaning packages..."

run_cmd sudo apt-get autoremove -y
run_cmd sudo apt-get autoclean