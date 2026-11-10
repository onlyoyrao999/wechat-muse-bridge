#!/usr/bin/env bash
# Supervisor for the WeChat bridge daemon (~/workspace/WeChat-bridge).
#
# Why this exists: the daemon kept dying silently every ~2 minutes when it
# was started from a hook worker's shell (its process group was reaped when
# the worker turn ended), with no traceback anywhere. Two fixes in one:
#   1. the daemon is started in its own session (setsid) so no parent's
#      cleanup can reach it;
#   2. this loop restarts it within 2 s if it ever exits, and logs the exit
#      code so the next death leaves evidence.
#
# Start it detached (once): setsid nohup "$BRIDGE/supervise-daemon.sh" \
#   >> "$BRIDGE/logs/supervisor.log" 2>&1 < /dev/null &
# On session expiry it does NOT restart (a rescan is needed instead) and
# exits so the hook can tell the user.
set -u

BRIDGE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$BRIDGE/logs/supervisor.log"
mkdir -p "$BRIDGE/logs"

echo "$(date '+%F %T') supervisor starting (pid $$)" >> "$LOG"

while true; do
  if [ -e "$BRIDGE/state/flags/session_expired" ]; then
    echo "$(date '+%F %T') session expired, not restarting" >> "$LOG"
    exit 0
  fi
  setsid "$BRIDGE/.venv/bin/python" "$BRIDGE/daemon.py" \
    >> "$BRIDGE/logs-daemon.txt" 2>&1 &
  DAEMON_PID=$!
  wait "$DAEMON_PID"
  code=$?
  echo "$(date '+%F %T') daemon exited code=$code" >> "$LOG"
  if [ -e "$BRIDGE/state/flags/session_expired" ]; then
    echo "$(date '+%F %T') session expired, not restarting" >> "$LOG"
    exit 0
  fi
  sleep 2
done
