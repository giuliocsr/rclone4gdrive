#!/bin/sh

# rclone-fail-handler.sh
#
# Called by rclone-fail.service when rclone.service exits non-zero. It inspects
# the last journal lines and classifies the failure:
#
#   - Transient network errors (DNS, TCP, timeouts): the timer is left
#     running; the next hourly sync retries on its own.
#   - "Must run --resync to recover.": the timer is stopped while a --resync
#     runs (so the hourly trigger cannot race it), then restarted on success.
#   - Auth errors (invalid_grant, expired/revoked token): retrying cannot
#     succeed until the user re-authorizes; the journal gets instructions and
#     the timer stays armed so syncing self-heals after re-auth.
#   - Anything else: unknown failure; the timer stays armed and the failure
#     remains visible in `rclone4gdrive status` until a sync succeeds.
#
# The timer is only ever stopped around the --resync attempt, so a single
# failed sync can never silently disable scheduled syncing (a past one-off DNS
# failure used to leave the timer stopped for good).
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

# Collect journal lines for the rclone service, scoped to the failed run.
# This handler fires seconds after the failure (OnFailure=), so a short
# time window reliably captures the failed run's error lines while excluding
# errors from earlier runs that may still linger in the tail of the journal
# (a silent successful sync leaves no rclone lines, so a purely line-counted
# window could reach back days and act on a stale error).
JOURNAL_OUTPUT=$(journalctl --user -u rclone.service --since=-15min -n 30 --no-pager 2>/dev/null || true)

# --- Transient network errors ---
# Checked FIRST: network failures often embed token-related text (a DNS error
# while rclone fetches a token reads "... couldn't fetch token: ... server
# misbehaving"), so they must not be mistaken for an auth problem.
if echo "$JOURNAL_OUTPUT" | grep -E -q "dial tcp|no such host|server misbehaving|Temporary failure in name resolution|network is unreachable|connection refused|connection reset by peer|context deadline exceeded|Client\.Timeout|i/o timeout|TLS handshake timeout"; then
  echo "Transient network failure detected. Leaving rclone.timer running; the next scheduled sync will retry."
  exit 0
fi

# --- Bisync resync-required handling ---
# A --resync can run long on large trees, so stop the timer first to keep the
# hourly trigger from racing it; restart everything on success, leave the timer
# stopped (asking for manual intervention) on failure.
if echo "$JOURNAL_OUTPUT" | grep -q "Must run --resync to recover."; then
  echo "Detected 'Must run --resync to recover.' in logs. Attempting resync..."
  systemctl --user stop rclone.timer || true
  # Attempt to recover by running rclone with --resync (common flags from config.sh).
  # shellcheck disable=SC2086  # intentional word-splitting of BISYNC_COMMON_FLAGS
  if "$RCLONE_BIN" bisync "${REMOTE}:" "$SYNC_DIR"/ --resync $BISYNC_COMMON_FLAGS --log-level=ERROR; then
    restart_services
  else
    echo "rclone --resync failed. Timer left stopped to avoid repeating a broken resync; run: rclone4gdrive status"
    exit 1
  fi
fi

# --- Auth errors ---
# rclone refreshes access tokens by itself whenever the network is up, so
# invalid_grant / a revoked refresh token only clears after manual
# re-authorization. Keep the timer armed: once the user re-authorizes, the
# next scheduled sync resumes syncing without any further action.
if echo "$JOURNAL_OUTPUT" | grep -E -q "invalid_grant|Token has been expired or revoked|invalid_client"; then
  echo "Auth failure detected (token rejected, expired, or revoked). Re-authorize with:"
  echo "  rclone config reconnect ${REMOTE}:   (or re-run: rclone4gdrive init)"
  echo "The timer stays armed; syncing resumes automatically after re-authorization."
  exit 0
fi

# --- Unknown failures ---
# Not a known pattern: leave the timer running. A transient cause self-heals on
# the next hourly run; a persistent one keeps failing visibly in
# `rclone4gdrive status` without ever disabling scheduled syncing.
echo "Sync failed with an unrecognized error. Timer left running; next scheduled sync will retry."
echo "Inspect: journalctl --user -u rclone.service"
exit 0
