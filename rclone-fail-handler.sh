#!/bin/sh

# rclone-fail-handler.sh
#
# Called by rclone-fail.service. It stops rclone.timer to prevent further
# scheduled runs, inspects recent logs for known failure patterns, and attempts
# automated recovery such as refreshing the OAuth token or running a --resync.
# On success it restarts the timer/service; otherwise it leaves the timer
# stopped and instructs the user to intervene manually.
#
# Shared settings (REMOTE, RCLONE_BIN, SYNC_DIR, BISYNC_COMMON_FLAGS) come from
# config.sh, sourced below.

# Resolve this script's directory (works even when invoked via PATH) and load
# shared configuration.
case "$0" in
  */*) _self=$0 ;;
  *)
    _self=$(command -v "$0")
    [ -n "$_self" ] || _self="./$0"
    ;;
esac
SCRIPT_DIR=$(unset CDPATH; cd "$(dirname -- "$_self")" && pwd)
# shellcheck disable=SC1090  # dynamic path; config.sh ships next to this script
. "$SCRIPT_DIR/config.sh"

# Function to restart the rclone.timer and service using the rclone4gdrive helper script.
restart_services() {
  echo "Restarting rclone.timer and service via rclone4gdrive..."
  "$SCRIPT_DIR/rclone4gdrive" restart || {
    echo "Failed to restart rclone.timer/service automatically. Please run manually."
    exit 1
  }
  echo "Timer and service restarted."
  exit 0
}

# Stop the timer immediately to avoid further scheduled runs while we handle the failure.
systemctl --user stop rclone.timer || true

# Collect recent journal lines for the rclone service (last 10 lines).
JOURNAL_OUTPUT=$(journalctl --user -u rclone.service -n 10 --no-pager 2>/dev/null || true)

# --- OAuth/token error handling block ---
if echo "$JOURNAL_OUTPUT" | grep -E -q "couldn't fetch token|invalid_grant|Token has been expired or revoked|couldn't find root directory ID"; then
  echo "Detected invalid token in logs. Attempting refresh..."
  if "$SCRIPT_DIR/refresh_token.sh"; then
    restart_services
  else
    echo "refresh token failed."
  fi
fi

# Check for the "Must run --resync to recover." error in the logs.
if echo "$JOURNAL_OUTPUT" | grep -q "Must run --resync to recover."; then
  echo "Detected 'Must run --resync to recover.' in logs. Attempting resync..."
  # Attempt to recover by running rclone with --resync (common flags from config.sh).
  # shellcheck disable=SC2086  # intentional word-splitting of BISYNC_COMMON_FLAGS
  if "$RCLONE_BIN" bisync "${REMOTE}:" "$SYNC_DIR"/ --resync $BISYNC_COMMON_FLAGS --log-level=ERROR; then
    restart_services
  else
    echo "rclone --resync failed."
  fi
else
  # No known recoverable error found; inform the user and exit.
  echo "No OAuth/token error or resync required detected in recent logs. Timer has been stopped as part of failure handling."
  exit 0
fi
