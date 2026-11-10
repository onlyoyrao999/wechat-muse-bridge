#!/usr/bin/env python3
"""Connect the official WeChat login to the Muse bridge.

Takes the fresh login the official CLI saved under
~/.openclaw/openclaw-weixin/accounts/ and wires it into bridge/:
writes bridge/state/credentials.json (0600), stops the OpenClaw gateway
so only one client polls the session, kills any stale bridge daemon,
starts the daemon, and verifies the cursor is updating.

Usage:
    python3 scripts/connect_muse.py [--bridge-dir DIR]

Run this after scripts/official_login.py succeeds. If the official
gateway watchdog is enabled, disable it first — otherwise it will
restart the gateway and the two clients will fight over the session.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import signal
import subprocess
import sys
import time

ACCOUNTS_GLOB = os.path.expanduser(
    "~/.openclaw/openclaw-weixin/accounts/*-im-bot.json")


def pids_matching(pattern: str) -> list[int]:
    out = subprocess.run(["pgrep", "-f", pattern],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return []
    return [int(p) for p in out.stdout.split() if p.strip()]


def kill_pids(pids: list[int], name: str) -> None:
    for pid in pids:
        if pid == os.getpid():
            continue
        try:
            os.kill(pid, signal.SIGTERM)
            print(f"stopped {name} pid={pid}")
        except ProcessLookupError:
            pass


def newest_account() -> tuple[str, dict]:
    files = sorted(glob.glob(ACCOUNTS_GLOB), key=os.path.getmtime)
    if not files:
        print("no official login found under ~/.openclaw/openclaw-weixin/accounts/",
              file=sys.stderr)
        print("run scripts/official_login.py first", file=sys.stderr)
        sys.exit(2)
    path = files[-1]
    with open(path, encoding="utf-8") as f:
        return path, json.load(f)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bridge-dir",
                    default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                         "..", "bridge"))
    args = ap.parse_args()
    bridge = os.path.abspath(args.bridge_dir)
    acct_path, acct = newest_account()
    account_id = os.path.basename(acct_path).removesuffix(".json")
    payload = {
        "token": acct["token"],
        "base_url": acct.get("baseUrl") or "https://ilinkai.weixin.qq.com",
        "account_id": account_id,
        "user_id": acct.get("userId"),
        "saved_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    state = os.path.join(bridge, "state")
    os.makedirs(os.path.join(state, "flags"), exist_ok=True)
    cred_path = os.path.join(state, "credentials.json")
    with open(cred_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
    os.chmod(cred_path, 0o600)
    print(f"credentials written from {account_id} (0600)")

    flag = os.path.join(state, "flags", "session_expired")
    if os.path.exists(flag):
        os.unlink(flag)
        print("cleared stale session_expired flag")

    # One poller only: stop the gateway and any stale bridge daemon.
    kill_pids(pids_matching("openclaw-gateway"), "openclaw gateway")
    kill_pids([p for p in pids_matching(os.path.join(bridge, "daemon.py"))],
              "stale bridge daemon")
    time.sleep(2)

    for d in ("inbox", "outbox", "media", "logs"):
        os.makedirs(os.path.join(bridge, d), exist_ok=True)
    venv_python = os.path.join(bridge, ".venv", "bin", "python")
    python = venv_python if os.path.exists(venv_python) else sys.executable
    log = open(os.path.join(bridge, "logs-daemon.txt"), "ab")
    proc = subprocess.Popen(
        [python, os.path.join(bridge, "daemon.py")],
        cwd=bridge, stdout=log, stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL, start_new_session=True)
    print(f"bridge daemon started pid={proc.pid}")

    time.sleep(45)
    cursor = os.path.join(state, "cursor.txt")
    ok = (proc.poll() is None
          and os.path.exists(cursor)
          and time.time() - os.path.getmtime(cursor) < 120
          and not os.path.exists(flag))
    if ok:
        print("OK: daemon polling, cursor updating, session valid.")
        print("Send the bot a WeChat message to test end-to-end.")
        return 0
    print("FAILED: daemon not healthy after 45s — check "
          f"{os.path.join(bridge, 'logs', 'daemon.log')}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
