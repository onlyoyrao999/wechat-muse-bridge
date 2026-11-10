#!/usr/bin/env bash
# Triage for the WeChat bridge (~/workspace/WeChat-bridge): wake Muse the
# moment a new WeChat message lands in inbox/, or when the bridge daemon
# is unhealthy. Fast path replaces the 2-minute cron so replies take seconds.
set -euo pipefail
source "$HATCH_HOOK_RUNTIME"

BRIDGE="$HOME/workspace/WeChat-bridge"
MARK="$HOME/hooks/state/wechat-bridge-alerted.json"
mkdir -p "$HOME/hooks/state"

count=$(find "$BRIDGE/inbox" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
if [ "$count" -gt 0 ]; then
  wake "微信有 $count 条新消息" "{\"count\": $count}"
fi

# No new messages: check daemon health.
if [ -e "$BRIDGE/state/flags/session_expired" ]; then
  health="登录过期（session_expired）"
elif ! pgrep -f "daemon.py" >/dev/null 2>&1; then
  health="daemon 没在跑"
elif [ -z "$(find "$BRIDGE/state/cursor.txt" -mmin -10 2>/dev/null)" ]; then
  health="游标超过 10 分钟没更新"
else
  rm -f "$MARK"
  silent "微信桥正常，收件箱为空"
fi

# Unhealthy: wake once, then at most once an hour while it lasts.
if [[ "$HATCH_HOOK_DRY_RUN" != "1" ]]; then
  if [ -f "$MARK" ] && [ -z "$(find "$MARK" -mmin +60 2>/dev/null)" ]; then
    silent "微信桥异常已提醒过：$health"
  fi
  mkdir -p "$(dirname "$MARK")"
  touch "$MARK"
fi
wake "微信桥异常：$health" "{\"health\": \"$health\"}"
