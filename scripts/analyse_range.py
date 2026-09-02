"""Stage 5, what the mechanism would actually do on real mainnet traffic.

Everything here is COUNTED from logs. No counterfactual is modelled and none can be: what price
would have done had a trade been capped is unknowable, and modelling it would reintroduce the
reference-price problem that made the LP-value number meaningless in Stage 4.

Questions answered:
  1. how many distinct addresses clear N = 20 swaps
  2. the distribution of directional balance among them
  3. what depth fraction each would receive (fully determined; no free parameter)
  4. what share of historical volume would have exceeded a cap, across a range of tranche sizes
"""
import json, io, collections

BPS = 10000
BASE_DEPTH_BPS = 500
FULL_DEPTH_STANDING = 10000
MIN_STANDING_SWAPS = 20
USDC = 10**6  # token0 of this pool


def depth_fraction_bps(standing):
    """Mirrors TenureHook.depthFractionBps exactly."""
    if standing >= FULL_DEPTH_STANDING:
        return BPS
    return BASE_DEPTH_BPS + ((BPS - BASE_DEPTH_BPS) * standing) // FULL_DEPTH_STANDING


def i256(h):
    v = int(h, 16)
    return v - (1 << 256) if v >= (1 << 255) else v


logs = json.load(io.open("range_logs.json"))
blocks = sorted({int(l["blockNumber"], 16) for l in logs})
print(f"logs {len(logs)}   blocks {blocks[0]}..{blocks[-1]} ({blocks[-1]-blocks[0]+1} wide)")

acct = collections.defaultdict(lambda: {"buys": 0, "sells": 0, "sizes": []})
for l in logs:
    rcpt = "0x" + l["topics"][2][-40:]
    a0 = i256(l["data"][2:66])
    if a0 == 0:
        continue
    e = acct[rcpt]
    if a0 > 0:
        e["buys"] += 1
    else:
        e["sells"] += 1
    e["sizes"].append(abs(a0))

total_addr = len(acct)
total_swaps = sum(e["buys"] + e["sells"] for e in acct.values())
total_vol = sum(sum(e["sizes"]) for e in acct.values())

qualified = {a: e for a, e in acct.items() if e["buys"] + e["sells"] >= MIN_STANDING_SWAPS}
q_swaps = sum(e["buys"] + e["sells"] for e in qualified.values())
q_vol = sum(sum(e["sizes"]) for e in qualified.values())

print()
print("=== 1. who clears N = 20 ===")
print(f"  distinct addresses          : {total_addr}")
print(f"  clearing N=20 (have standing): {len(qualified)}  ({100*len(qualified)/max(total_addr,1):.1f}%)")
print(f"  swaps by them               : {q_swaps} / {total_swaps}  ({100*q_swaps/max(total_swaps,1):.1f}%)")
print(f"  volume by them              : {100*q_vol/max(total_vol,1):.1f}% of all volume")
print(f"  everyone else falls to base depth ({BASE_DEPTH_BPS} bps)")

print()
print("=== 2. directional balance among those with standing ===")
buckets = collections.Counter()
rows = []
for a, e in qualified.items():
    n = e["buys"] + e["sells"]
    bal = (2 * min(e["buys"], e["sells"]) * BPS) // n
    rows.append((a, n, e["buys"], e["sells"], bal, depth_fraction_bps(bal), sum(e["sizes"])))
    buckets[min(bal // 1000, 9)] += 1
for b in range(10):
    lo, hi = b * 1000, b * 1000 + 999
    bar = "#" * buckets[b]
    print(f"  {lo:5d}-{hi:5d} bps | {buckets[b]:3d} {bar}")

print()
print("=== 3. depth fraction they would receive (deterministic) ===")
rows.sort(key=lambda r: -r[6])
print(f"  {'address':44} {'swaps':>5} {'buy':>4} {'sell':>4} {'balance':>8} {'depth':>7}  {'volume(USDC)':>14}")
for a, n, b, s, bal, df, vol in rows[:12]:
    print(f"  {a:44} {n:5d} {b:4d} {s:4d} {bal:7d}b {df:6d}b  {vol/USDC:14,.0f}")
if len(rows) > 12:
    print(f"  ... and {len(rows)-12} more")

fulls = sum(1 for r in rows if r[5] == BPS)
print()
print(f"  at full depth (10000 bps): {fulls} of {len(rows)} with standing")

print()
print("=== 4. share of volume above the cap, by tranche size ===")
print("  tranche is an operator parameter, so it is reported across a range, not chosen.")
print(f"  {'tranche(USDC)':>14} {'capped swaps':>13} {'capped volume':>14} {'excess volume':>14}")
for tranche_usdc in [50_000, 100_000, 250_000, 500_000, 1_000_000, 5_000_000]:
    tranche = tranche_usdc * USDC
    capped_n = capped_v = excess = 0
    tot_n = 0
    for a, e in acct.items():
        n = e["buys"] + e["sells"]
        if n >= MIN_STANDING_SWAPS:
            bal = (2 * min(e["buys"], e["sells"]) * BPS) // n
            df = depth_fraction_bps(bal)
        else:
            df = BASE_DEPTH_BPS
        cap = tranche * df // BPS
        for sz in e["sizes"]:
            tot_n += 1
            if sz > cap:
                capped_n += 1
                capped_v += sz
                excess += sz - cap
    print(f"  {tranche_usdc:14,} {capped_n:6d}/{tot_n:<6d} {100*capped_v/max(total_vol,1):13.1f}% {100*excess/max(total_vol,1):13.1f}%")

json.dump({"total_addr": total_addr, "qualified": len(qualified), "total_swaps": total_swaps,
           "blocks": [blocks[0], blocks[-1]], "rows": [[r[0], r[1], r[2], r[3], r[4], r[5]] for r in rows]},
          io.open("range_summary.json", "w"), indent=1)
print()
print("saved range_summary.json")
