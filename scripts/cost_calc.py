#!/usr/bin/env python3
"""
Part III cost reality check: Lambda vs always-on ECS.

    python3 scripts/cost_calc.py            # table + break-even
    python3 scripts/cost_calc.py 50000      # one specific monthly volume
"""
import sys

REQ_PRICE = 0.20 / 1_000_000     # $ per request
GBS_PRICE = 0.0000166667         # $ per GB-second (x86)
FREE_REQ, FREE_GBS = 1_000_000, 400_000
SECONDS, GB = 3, 0.5             # 3 s payment check, 512 MB
ECS = 17.00                      # 2 tasks x $8.50 (assignment's figure)


def lambda_cost(orders):
    gbs = orders * SECONDS * GB
    return max(0, orders - FREE_REQ) * REQ_PRICE + max(0, gbs - FREE_GBS) * GBS_PRICE


def break_even():
    lo, hi = 0, 100_000_000
    while hi - lo > 1:
        mid = (lo + hi) // 2
        lo, hi = (mid, hi) if lambda_cost(mid) < ECS else (lo, mid)
    return hi


if len(sys.argv) > 1:
    n = int(sys.argv[1].replace(",", ""))
    print(f"{n:,} orders/month -> Lambda ${lambda_cost(n):,.2f} vs ECS ${ECS:.2f}")
    sys.exit()

print(f"Per order: {SECONDS} s x {GB} GB = {SECONDS*GB} GB-s; "
      f"GB-s free tier covers {FREE_GBS/(SECONDS*GB):,.0f} orders/month\n")
print("| Orders / month | GB-seconds | Lambda $ | ECS $ | Cheaper |")
print("|---|---|---|---|---|")
for n in [10_000, 100_000, 266_667, 500_000, 946_667, 1_000_000, 1_700_000, 5_000_000, 10_000_000]:
    c = lambda_cost(n)
    print(f"| {n:,} | {n*SECONDS*GB:,.0f} | {c:,.2f} | {ECS:.2f} | {'Lambda' if c < ECS else 'ECS'} |")
be = break_even()
print(f"\nBreak-even: ~{be:,} orders/month (Lambda = ${ECS:.2f}).")
print("Beyond the free tier each order costs about $%.7f, almost all of it compute "
      "(GB-s), not the request fee." % (REQ_PRICE + SECONDS * GB * GBS_PRICE))
print("Flash sale check: 60 orders/s x 3 s = 180 concurrent executions needed; "
      "the default account limit is 1,000, and Learner Lab accounts are often capped near 10.")
