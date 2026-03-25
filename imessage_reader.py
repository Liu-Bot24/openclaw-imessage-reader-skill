#!/usr/bin/env python3
"""Read recent iMessage/SMS by delegating to the compiled imessage-db-reader binary.

This script does NOT access chat.db directly. It calls the dedicated
imessage-db-reader binary (which is the only process that needs FDA),
parses its JSON output, and formats the result.

The binary is launched via launchctl submit so that launchd is the
responsible process for TCC purposes — this avoids requiring FDA on
node/python/Terminal.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

READER_BIN = Path(__file__).parent / "imessage-db-reader"
LAUNCHCTL_LABEL_PREFIX = "ai.openclaw.imessage-reader-"


def call_reader(args: argparse.Namespace) -> list[dict]:
    if not READER_BIN.exists():
        print(
            f"ERROR: {READER_BIN} not found.\n"
            "Compile it with: swiftc -O -o imessage-db-reader imessage-db-reader.swift -lsqlite3",
            file=sys.stderr,
        )
        sys.exit(1)

    cmd = [str(READER_BIN), "--minutes", str(args.minutes), "--limit", str(args.limit)]

    if args.type != "all":
        cmd += ["--type", args.type]
    if args.sender:
        cmd += ["--sender", args.sender]
    if args.receiver:
        cmd += ["--receiver", args.receiver]
    if args.content:
        cmd += ["--content", args.content]
    if args.include_sent:
        cmd.append("--include-sent")

    job_id = uuid.uuid4().hex[:8]
    label = LAUNCHCTL_LABEL_PREFIX + job_id
    stdout_path = os.path.join(tempfile.gettempdir(), f"imsg-out-{job_id}.txt")
    stderr_path = os.path.join(tempfile.gettempdir(), f"imsg-err-{job_id}.txt")

    try:
        launchctl_cmd = [
            "launchctl", "submit", "-l", label,
            "-o", stdout_path, "-e", stderr_path,
            "--", *cmd,
        ]
        sub = subprocess.run(launchctl_cmd, capture_output=True, timeout=5)
        if sub.returncode != 0:
            msg = sub.stderr.decode(errors="replace").strip() if sub.stderr else "unknown"
            print(f"ERROR: launchctl submit failed: {msg}", file=sys.stderr)
            sys.exit(1)

        poll_interval = 0.3
        poll_rounds = 40
        timeout_sec = int(poll_interval * poll_rounds)
        for _ in range(poll_rounds):
            time.sleep(poll_interval)

            err = ""
            if os.path.exists(stderr_path):
                with open(stderr_path) as f:
                    err = f.read().strip()
            if err:
                print(err, file=sys.stderr)
                sys.exit(1)

            if os.path.exists(stdout_path):
                with open(stdout_path) as f:
                    raw = f.read().strip()
                if raw:
                    try:
                        return json.loads(raw)
                    except json.JSONDecodeError:
                        continue

        if os.path.exists(stdout_path):
            with open(stdout_path) as f:
                raw = f.read().strip()
            if raw:
                return json.loads(raw)

        print(f"ERROR: imessage-db-reader produced no output within {timeout_sec}s", file=sys.stderr)
        sys.exit(1)

    except json.JSONDecodeError as e:
        print(f"ERROR: failed to parse reader output: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        subprocess.run(["launchctl", "remove", label],
                        capture_output=True, timeout=3)
        for p in (stdout_path, stderr_path):
            try:
                os.unlink(p)
            except OSError:
                pass


def format_output(messages: list[dict], output_format: str) -> str:
    if not messages:
        return "最近没有符合条件的消息。"

    if output_format == "json":
        return json.dumps(messages, ensure_ascii=False, indent=2)

    lines = [f"共 {len(messages)} 条消息：\n"]
    for i, m in enumerate(messages, 1):
        lines.append(
            f"[{i}] {m['time']}  {m['type']}\n"
            f"    发送方: {m['sender']}\n"
            f"    接收方: {m['receiver']}\n"
            f"    内容: {m['content']}\n"
        )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Read recent iMessage/SMS from local Messages database"
    )
    parser.add_argument(
        "--minutes", type=int, default=30,
        help="How many minutes back to look (default: 30)",
    )
    parser.add_argument(
        "--type",
        choices=["sms", "imessage", "rcs", "all"],
        default="all",
        help="Filter by message service type (default: all)",
    )
    parser.add_argument(
        "--sender", type=str, default=None,
        help="Regex pattern to filter sender number/address",
    )
    parser.add_argument(
        "--receiver", type=str, default=None,
        help="Regex pattern to filter receiver number/address",
    )
    parser.add_argument(
        "--content", type=str, default=None,
        help="Regex pattern to filter message content",
    )
    parser.add_argument(
        "--limit", type=int, default=50,
        help="Max messages to return (default: 50)",
    )
    parser.add_argument(
        "--include-sent", action="store_true",
        help="Also include messages sent by you",
    )
    parser.add_argument(
        "--format", choices=["text", "json"], default="text",
        help="Output format (default: text)",
    )
    args = parser.parse_args()

    messages = call_reader(args)
    print(format_output(messages, args.format))
    return 0


if __name__ == "__main__":
    sys.exit(main())
