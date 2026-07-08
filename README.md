# system-maintenance

A small, modular Bash toolkit for routine Linux system maintenance:
package updates, cache/journal cleanup, developer-tool cache pruning,
and a reboot check — all with dry-run support, logging, and safe
configuration handling.

## Features

- **Dry-run mode** — preview every command before it touches the system.
- **Structured logging** — every action is timestamped and written to
  both the console and a persistent log file.
- **Fail-fast with context** — `set -Eeuo pipefail` plus an error trap
  reports the exact line and exit code if something goes wrong.
- **Modular phases** — each maintenance step lives in its own file
  under `modules/`, so you can add, remove, or reorder steps easily.
- **Safe config loading** — an optional config file can override
  defaults, but is only sourced if it's owned by you and not
  writable by anyone else.

## Requirements

- Bash 4+ (uses `[[ ]]`, `BASH_SOURCE`, etc.)
- A Debian/Ubuntu-based system (`apt-get`, `journalctl`, `systemd-tmpfiles`)
- `sudo` privileges for most operations
- Optional: `fwupdmgr` (firmware updates), `docker` (container cache
  cleanup), `needrestart` (better reboot detection)

None of the optional tools are required — each module checks for the
relevant command with `command -v` and skips gracefully if it's missing.

## Project layout

```
system-maintenance/
├── main.sh          # Main entry point / orchestrator
├── lib/
│   └── helpers.sh          # Logging, run_cmd(), disk usage, reboot check
└── modules/
    ├── 01_update.sh        # Phase 1: apt update/upgrade, firmware
    ├── 02_cleanup.sh       # Phase 2: apt autoremove/autoclean
    ├── 03_system.sh        # Phase 3: tmpfiles cleanup, journal vacuum
    ├── 04_dev.sh           # Phase 4: Docker (and other dev) cache cleanup
    └── 05_health.sh        # Phase 5: reboot-required check
```

## Installation

1. Copy the `system-maintenance/` directory anywhere on the target
   machine, e.g. `/opt/system-maintenance` or `~/system-maintenance`.
2. Make the scripts executable (only needed once):
   ```bash
   chmod +x main.sh lib/helpers.sh modules/*.sh
   ```
3. (Optional) Run it on a schedule with cron or a systemd timer.

## Usage

```bash
./main.sh [options]
```

| Option              | Description                                                        |
|---------------------|----------------------------------------------------------------------|
| `-n`, `--dry-run`   | Print what would be executed without making any changes.           |
| `-v`, `--verbose`   | Enable verbose shell tracing (`set -x`) for debugging.             |
| `--auto-reboot`     | Automatically reboot if the system reports a reboot is required.   |
| `--aggressive`      | Also prune unused Docker **volumes** during Phase 4 (destructive).  |
| `-h`, `--help`      | Show usage and exit.                                                |

### Examples

Preview everything without changing anything:
```bash
./main.sh --dry-run
```

Run for real, and reboot automatically if the kernel was updated:
```bash
./main.sh --auto-reboot
```

Run with aggressive Docker cleanup (removes unused volumes — make sure
you don't need any stopped-container data first):
```bash
./main.sh --aggressive
```

## Configuration file

On startup, `main.sh` looks for `~/.config/system-maintenance.conf`
and sources it if present, letting you override any default without
editing the scripts. Example:

```bash
# ~/.config/system-maintenance.conf
AUTO_REBOOT=true
AGGRESSIVE_CLEAN=false
JOURNAL_RETENTION="14d"
```

**Security note:** because this file is sourced as shell code, it's
only loaded if it's owned by the current user and not writable by
group or others. Lock it down with:

```bash
chmod 600 ~/.config/system-maintenance.conf
```

If the permissions aren't safe, `main.sh` logs a warning and
skips the file rather than sourcing it.

## Logging

All output is timestamped (`YYYY-MM-DD HH:MM:SS`) and written to
`~/system-maintenance.log` (override with the `LOGFILE` environment
variable or from the config file). `INFO` lines go to stdout, `WARN`
and `ERROR` lines go to stderr — both are also captured in the log
file.

## What each phase does

1. **Update** — `apt-get update`, `apt-get full-upgrade -y`, and
   firmware updates via `fwupdmgr` if installed.
2. **Cleanup** — removes no-longer-needed packages (`autoremove`) and
   clears the local package cache (`autoclean`).
3. **System cleanup** — clears stale `systemd-tmpfiles` and vacuums
   the systemd journal down to `JOURNAL_RETENTION` (default `7d`).
4. **Dev environment cleanup** — prunes unused Docker images/containers
   (and volumes, with `--aggressive`). Add more caches (npm, pip,
   cargo, etc.) directly in `modules/04_dev.sh`.
5. **Health check** — checks `/var/run/reboot-required` and
   `needrestart` for a pending reboot, then reboots automatically only
   if `--auto-reboot`/`AUTO_REBOOT` is set.

## Exit behavior

The script uses `set -Eeuo pipefail` with a global error trap: if any
command fails, `main.sh` stops immediately, logs the failing
line number and exit code, and exits with that same code — it won't
silently continue into later phases after a failure.

## Extending

To add a new maintenance step:

1. Create `modules/06_yourstep.sh` following the existing pattern
   (a header comment, then calls to `log`/`run_cmd`).
2. Add `source "./modules/06_yourstep.sh"` to `main.sh` in the
   **Run** section, in the order you want it executed.