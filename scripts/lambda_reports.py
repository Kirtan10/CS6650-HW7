#!/usr/bin/env python3
"""Reads `aws logs filter-log-events --output json` on stdin -> cold/warm table."""
import sys, json, re, datetime

events = json.load(sys.stdin).get("events", [])
if not events:
    print("No REPORT lines yet. Logs can lag ~30 s: wait and rerun.")
    sys.exit()

def g(key, msg):
    m = re.search(key + r": ([\d.]+)", msg)
    return m.group(1) if m else None

print("| Time (UTC) | Type | Duration (ms) | Billed (ms) | Max mem (MB) | Init (ms) | Overhead |")
print("|---|---|---|---|---|---|---|")
cold = []
for e in sorted(events, key=lambda e: e["timestamp"]):
    msg = e["message"]
    t = datetime.datetime.fromtimestamp(e["timestamp"] / 1000, datetime.timezone.utc).strftime("%H:%M:%S")
    d, b = g("Duration", msg), g("Billed Duration", msg)
    mem, init = g("Max Memory Used", msg), g("Init Duration", msg)
    kind = "COLD" if init else "warm"
    over = "-"
    if init:
        cold.append(float(init))
        over = f"{float(init) / float(d) * 100:.1f}%"
    print(f"| {t} | {kind} | {d} | {b} | {mem} | {init or '-'} | {over} |")
n = len(events)
print(f"\n{n} invocations, {len(cold)} cold starts ({len(cold) / n * 100:.0f}%)")
if cold:
    print(f"Init Duration: min {min(cold):.1f} ms, avg {sum(cold)/len(cold):.1f} ms, max {max(cold):.1f} ms")
