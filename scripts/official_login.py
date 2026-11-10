#!/usr/bin/env python3
"""Official WeChat login, adapted so the QR code reaches the user.

Runs the Tencent official login (`openclaw channels login --channel
openclaw-weixin`), watches its output, and renders every QR URL it prints
as a numbered PNG file. The stock flow only prints the QR in the terminal,
which the user never sees on a headless VM; this wrapper is the adaptation
that makes the official login usable from a chat: send each new PNG to the
user the moment it appears, and never reuse a file path (chat clients cache
images by path — a reused path keeps showing the first, expired code).

Usage:
    python3 scripts/official_login.py [--qr-dir DIR] [--timeout SECONDS]

Each QR lives ~2 minutes server-side. The login command re-prints a fresh
QR when the old one expires and waits up to ~8 minutes total.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time

URL_RE = re.compile(
    r"https://liteapp\.weixin\.qq\.com/q/\S+?qrcode=([0-9a-f]+)&bot_type=3"
)
SUCCESS_MARKERS = ("已将此 OpenClaw 连接到微信", "login saved", "Login successful")


def render_qr(url: str, path: str) -> None:
    import qrcode

    img = qrcode.make(url, box_size=10, border=2).convert("RGB")
    img.save(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--qr-dir", default=os.path.expanduser("~/workspace"))
    ap.add_argument("--timeout", type=int, default=600)
    args = ap.parse_args()

    os.makedirs(args.qr_dir, exist_ok=True)
    try:
        import qrcode  # noqa: F401
    except ImportError:
        print("missing dependency: pip install 'qrcode[pil]' "
              "(or run scripts/install.sh first)", file=sys.stderr)
        return 2

    proc = subprocess.Popen(
        ["openclaw", "channels", "login", "--channel", "openclaw-weixin"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL, text=True, bufsize=1,
    )
    seen: set[str] = set()
    n = 0
    deadline = time.time() + args.timeout
    print("official login started, waiting for QR code ...", flush=True)
    try:
        assert proc.stdout is not None
        for line in proc.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            if any(m in line for m in SUCCESS_MARKERS):
                print("LOGIN OK", flush=True)
                return 0
            m = URL_RE.search(line)
            if m and m.group(0) not in seen:
                seen.add(m.group(0))
                n += 1
                qrid = m.group(1)
                path = os.path.join(
                    args.qr_dir, f"wx-official-qr-{n}-{qrid[:8]}.png")
                render_qr(m.group(0), path)
                print(f"QR #{n} id={qrid[:8]} -> {path}", flush=True)
            if time.time() > deadline:
                print("login timed out", file=sys.stderr, flush=True)
                proc.kill()
                return 1
    finally:
        if proc.poll() is None:
            proc.kill()
    return proc.wait()


if __name__ == "__main__":
    sys.exit(main())
