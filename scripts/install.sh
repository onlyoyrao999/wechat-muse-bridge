#!/usr/bin/env bash
# End-to-end install for wechat-muse-bridge.
# Installs OpenClaw + the official WeChat plugin, sets up the bridge venv
# and config. The plugin installer ends with an interactive QR login;
# scan it when it appears (codes live ~2 min). If that login does not
# complete, run: python3 scripts/official_login.py
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE="$ROOT/bridge"

if ! command -v node >/dev/null 2>&1; then
  echo "node is required (https://nodejs.org)" >&2
  exit 1
fi

if ! command -v openclaw >/dev/null 2>&1; then
  echo "installing openclaw ..."
  npm install -g openclaw
fi

echo "installing the official WeChat plugin (ends with a QR login) ..."
npx -y @tencent-weixin/openclaw-weixin-cli@latest install || {
  echo "plugin install/login did not finish — run scripts/official_login.py" >&2
}

echo "setting up the bridge venv ..."
python3 -m venv "$BRIDGE/.venv"
"$BRIDGE/.venv/bin/pip" install -q -r "$BRIDGE/requirements.txt"
mkdir -p "$BRIDGE"/{inbox,outbox,media,logs,state/flags,state/processed}
[ -f "$BRIDGE/config.json" ] || cp "$BRIDGE/config.example.json" "$BRIDGE/config.json"

echo
echo "Next:"
echo "  1. python3 scripts/official_login.py   # if not logged in yet"
echo "  2. python3 scripts/connect_muse.py     # wire the login into the bridge"
echo "  3. Install the hook: scripts/hooks/wechat-bridge-triage.sh"
echo "     (see README) and send the bot a WeChat message to test."
