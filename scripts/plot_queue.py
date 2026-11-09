#!/usr/bin/env python3
"""
Plot one or more queue_monitor CSVs on one chart and print the Phase 5 table.

    python3 scripts/plot_queue.py results/queue_workers_*.csv
    -> results/queue_depth.png + a markdown table (peak depth, time to zero)
"""
import csv
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

files = sys.argv[1:] or sorted(str(p) for p in Path("results").glob("queue_*.csv"))
if not files:
    sys.exit("no CSVs found; run scripts/queue_monitor.sh first")

fig, ax = plt.subplots(figsize=(10, 5))
print("| Run | Peak visible | Peak at (s) | Back to 0 at (s) | Drain time (s) |")
print("|---|---|---|---|---|")
for f in files:
    rows = list(csv.DictReader(open(f)))
    t = [int(r["elapsed_s"]) for r in rows]
    vis = [int(r["visible"]) for r in rows]
    inf = [int(r["in_flight"]) for r in rows]
    label = Path(f).stem.replace("queue_", "")
    ax.plot(t, vis, label=label)
    peak = max(vis)
    t_peak = t[vis.index(peak)]
    zero = next((t[i] for i in range(vis.index(peak), len(t)) if vis[i] + inf[i] == 0), None)
    drain = (zero - t_peak) if zero is not None else None
    print(f"| {label} | {peak} | {t_peak} | {zero if zero is not None else 'not reached'} | "
          f"{drain if drain is not None else '-'} |")

ax.set_xlabel("seconds since monitor start")
ax.set_ylabel("ApproximateNumberOfMessages (visible)")
ax.set_title("SQS queue depth during the 60 s flash sale")
ax.grid(alpha=0.3)
ax.legend()
out = Path("results/queue_depth.png")
out.parent.mkdir(exist_ok=True)
fig.tight_layout()
fig.savefig(out, dpi=150)
print(f"\nsaved {out}")
