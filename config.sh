#!/bin/sh

# config.sh
#
# Purpose: Single source of truth for the configuration shared by every
# rclone4gdrive shell script (rclone4gdrive, refresh_token.sh,
# rclone-fail-handler.sh). Each of those scripts sources this file with:
#     . "$SCRIPT_DIR/config.sh"
#
# The systemd unit rclone.service cannot source a file itself, so instead of
# duplicating the bisync flags inside the unit it calls
# `rclone4gdrive sync-service`, which sources this file. That keeps every
# synchronization invocation reading the SAME values, so flags can no longer
# drift between the timer, manual sync, failure recovery, and token checks.
#
# Edit the variables below to change the remote name, the local sync
# directory, or the common rclone bisync flags used across the whole system.

# Name of the rclone remote, as created by `rclone config` (default: gdrive).
REMOTE="gdrive"

# Local directory that mirrors the Google Drive root.
SYNC_DIR="$HOME/gdrive"

# Path to the rclone binary.
RCLONE_BIN="/usr/bin/rclone"

# Path to rclone's own configuration file (where the OAuth token lives).
# Edited by init (during authorization) and refresh_token.sh (during renewal).
RCLONE_CONF="$HOME/.config/rclone/rclone.conf"

# Common bisync flags applied to EVERY synchronization call: the automatic
# timer sync, manual `sync`, failure-recovery --resync, and the
# non-destructive token-verification dry-run. Callers add their own
# context-specific flags (--progress, --log-level, --resync, --dry-run) on top.
# This is intentionally a space-separated string that callers word-split.
BISYNC_COMMON_FLAGS="--drive-skip-gdocs --create-empty-src-dirs"
