#!/usr/bin/env bash
# Triage for the WeChat bridge (~/workspace/WeChat-bridge): wake Muse the
# moment a new WeChat message lands in inbox/, or when the bridge is
# unhealthy in a way that needs a human decision.
#
# The daemon is supervised, not babysat: the supervisor
# (supervise-daemon.sh) restarts it within 2 s of any exit, so this script
# only restarts the supervisor itself when it is missing, and only wakes
# an agent when the daemon keeps dying or the login expired. That keeps
# recovery at ~5 s instead of a full agent turn (~30-60 s), and avoids the
# old failure mode where a hook worker's own restart was reaped with its
# turn.
#
# Heartbeat: the daemon writes state/cursor.txt on every successful poll
# (every ~30-70 s). A live process with a stale heartbeat is stuck, not
# healthy — this script kills it so the supervisor restarts it in 2 s.
set -euo pipefail
source "$HATCH_HOOK_RUNTIME"

BRIDGE="$HOME/workspace/WeChat-bridge"
SUP="$BRIDGE/supervise-daemon.sh"
SUPLOG="$BRIDGE/logs/supervisor.log"
MARK="$HOME/hooks/state/wechat-bridge-alerted.json"
mkdir -p "$HOME/hooks/state"

# $ anchor: a worker shell whose command line merely *contains* a daemon
# start command must not count as the daemon itself. The daemon's cmdline
# ends with "daemon.py" (relative or absolute path); a wrapper shell's
# command line continues past it.
daemon_alive() { pgrep -f 'python .*daemon\.py$' >/dev/null 2>&1; }
supervisor_alive() { pgrep -f 'supervise-daemon\.sh$' >/dev/null 2>&1; }

# Dedup: wake at most once per inbox message. The poll runs every 5 s
# and a worker can take 30-60 s (e.g. generating an image), so without
# this the same message wakes a new worker every 5 s and each one writes
# its own reply -> the same image/text sent twice or three times
# (seen 2026-11-10 19:55: "行，再来一张。" woke 10 workers). One marker
# file per message id; a marker expires after 10 min so a message whose
# worker died still gets re-woken. A worker claims a message by moving it
# to state/processing/ first; if it dies there, the sweep below puts it
# back in inbox/ after 10 min.
WOKEN_DIR="$HOME/hooks/state/wechat-bridge-woken"
mkdir -p "$WOKEN_DIR" "$BRIDGE/state/processing"
if [[ "$HATCH_HOOK_DRY_RUN" != "1" ]]; then
  for f in "$BRIDGE/state/processing"/*.json; do
    [ -e "$f" ] || continue
    if [ -n "$(find "$f" -mmin +10 2>/dev/null)" ]; then
      mv "$f" "$BRIDGE/inbox/" 2>/dev/null || true
      log "observation" '{"action":"requeued_stale_processing"}'
    fi
  done
fi
new=0
for f in "$BRIDGE/inbox"/*.json; do
  [ -e "$f" ] || continue
  id=$(basename "$f" .json | sed 's/^[0-9]*-//')
  marker="$WOKEN_DIR/$id"
  if [ -e "$marker" ]; then
    if [ -n "$(find "$marker" -mmin +10 2>/dev/null)" ]; then
      [[ "$HATCH_HOOK_DRY_RUN" != "1" ]] && rm -f "$marker"
    else
      continue
    fi
  fi
  [[ "$HATCH_HOOK_DRY_RUN" != "1" ]] && touch "$marker"
  new=$((new + 1))
done
if [[ "$HATCH_HOOK_DRY_RUN" != "1" ]]; then
  for m in "$WOKEN_DIR"/*; do
    [ -e "$m" ] || continue
    mid=$(basename "$m")
    if ! ls "$BRIDGE/inbox"/*-"$mid".json >/dev/null 2>&1; then
      rm -f "$m"
    fi
  done
fi
if [ "$new" -gt 0 ]; then
  wake "微信有 $new 条新消息" "{\"count\": $new}"
fi

# Session expired: only a rescan fixes it — wake the agent to tell Richard.
if [ -e "$BRIDGE/state/flags/session_expired" ]; then
  wake "微信桥登录过期，需要重新扫码" '{"health": "session_expired"}'
fi

daemon_pid() { pgrep -f 'python .*daemon\.py$' | head -1; }

if daemon_alive; then
  # Heartbeat check: cursor.txt is written on every successful poll.
  # Stale heartbeat + live process = stuck daemon, not a healthy one.
  # Age guard: a freshly (re)started daemon needs up to ~70 s for its
  # first poll to write the cursor — never kill one younger than 100 s,
  # or the restart itself becomes a kill loop.
  stale=0
  pid=$(daemon_pid)
  age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || true)
  if [ -n "$age" ] && [ "$age" -gt 100 ]; then
    if [ ! -e "$BRIDGE/state/cursor.txt" ]; then
      stale=1
    elif [ -z "$(find "$BRIDGE/state/cursor.txt" -mmin -3 2>/dev/null)" ]; then
      stale=1
    fi
  fi
  if [ "$stale" = 1 ]; then
    pid=$(daemon_pid)
    if [ -n "$pid" ]; then
      kill "$pid" 2>/dev/null || true
      log "observation" "{\"action\":\"killed_stuck_daemon\",\"pid\":$pid}"
    fi
    silent "微信桥 daemon 心跳停了，已杀掉，supervisor 2 秒内重启"
  fi
  rm -f "$MARK"
  silent "微信桥正常，收件箱为空"
fi

# Daemon down. If the supervisor is missing, start it (detached, own
# session); it restarts the daemon within 2 s.
if ! supervisor_alive; then
  setsid nohup "$SUP" >> "$SUPLOG" 2>&1 < /dev/null &
  log "observation" '{"action":"supervisor_started"}'
  silent "微信桥 daemon 没在跑，已启动 supervisor，2 秒内自动重启"
fi

# Supervisor is running and will restart the daemon. Escalate only when
# the daemon keeps dying: more than 5 exits in the last 10 minutes.
recent=0
if [ -f "$SUPLOG" ]; then
  recent=$(awk -v since="$(date -d '10 minutes ago' '+%F %T')" \
    '$1" "$2 >= since && /daemon exited/' "$SUPLOG" 2>/dev/null | wc -l)
fi
if [ "$recent" -gt 5 ]; then
  if [[ "$HATCH_HOOK_DRY_RUN" != "1" ]]; then
    if [ -f "$MARK" ] && [ -z "$(find "$MARK" -mmin +60 2>/dev/null)" ]; then
      silent "微信桥反复重启已提醒过"
    fi
    touch "$MARK"
  fi
  wake "微信桥 daemon 10 分钟内掉了 $recent 次" "{\"restarts\": $recent}"
fi
silent "微信桥 daemon 没在跑，supervisor 正在重启（2 秒内）"
