"""Two-pool replay. Identical mechanism constants and identical code path for every pool;
only the pool address, the volume leg and its decimals change.

Volume is measured on the WETH leg for the volatile pools and on the USDC leg for USDC/WETH,
which is the leg the published Stage 5 figures use. Every SHARE reported is unit-free, so the
cross-pool comparison does not depend on that choice; only the absolute tranche sweep does.
"""
import json, io, collections, sys

BPS = 10000
BASE_DEPTH_BPS = 500
FULL_DEPTH_STANDING = 10000
MIN_STANDING_SWAPS = 20


def depth_fraction_bps(standing):
    """Mirrors TenureHook.depthFractionBps exactly."""
    if standing >= FULL_DEPTH_STANDING:
        return BPS
    return BASE_DEPTH_BPS + ((BPS - BASE_DEPTH_BPS) * standing) // FULL_DEPTH_STANDING


def i256(h):
    v = int(h, 16)
    return v - (1 << 256) if v >= (1 << 255) else v


def analyse(path, label, vol_leg, vol_dec, unit):
    logs = json.load(io.open(path))
    blocks = sorted({int(l["blockNumber"], 16) for l in logs})
    acct = collections.defaultdict(lambda: {"buys": 0, "sells": 0, "sizes": []})
    for l in logs:
        rcpt = "0x" + l["topics"][2][-40:]
        a0 = i256(l["data"][2:66])
        a1 = i256(l["data"][66:130])
        if a0 == 0:
            continue                       # direction undefined; same rule as Stage 5
        e = acct[rcpt]
        (e.__setitem__("buys", e["buys"] + 1) if a0 > 0
         else e.__setitem__("sells", e["sells"] + 1))
        e["sizes"].append(abs(a0 if vol_leg == 0 else a1))

    total_addr = len(acct)
    total_swaps = sum(e["buys"] + e["sells"] for e in acct.values())
    total_vol = sum(sum(e["sizes"]) for e in acct.values())
    qual = {a: e for a, e in acct.items() if e["buys"] + e["sells"] >= MIN_STANDING_SWAPS}
    q_swaps = sum(e["buys"] + e["sells"] for e in qual.values())
    q_vol = sum(sum(e["sizes"]) for e in qual.values())

    # per-address standing and depth
    rows = []
    for a, e in acct.items():
        n = e["buys"] + e["sells"]
        if n >= MIN_STANDING_SWAPS:
            bal = (2 * min(e["buys"], e["sells"]) * BPS) // n
            df = depth_fraction_bps(bal)
            measured = True
        else:
            bal, df, measured = 0, BASE_DEPTH_BPS, False
        rows.append({"addr": a, "n": n, "buys": e["buys"], "sells": e["sells"],
                     "bal": bal, "df": df, "vol": sum(e["sizes"]), "measured": measured})

    vw = sum(r["df"] * r["vol"] for r in rows) / max(total_vol, 1)
    sw = sum(r["df"] * r["n"] for r in rows) / max(total_swaps, 1)

    # balance-band distribution, by SHARE OF VOLUME, over everyone
    bands = collections.OrderedDict((b, 0) for b in range(0, 10000, 2000))
    for r in rows:
        bands[min((r["bal"] // 2000) * 2000, 8000)] += r["vol"]

    # low-band decomposition
    low_one_sided = sum(r["vol"] for r in rows if r["measured"] and r["bal"] < 2000)
    low_unmeasured = sum(r["vol"] for r in rows if not r["measured"])
    n_one_sided = sum(1 for r in rows if r["measured"] and r["bal"] < 2000)
    n_unmeasured = sum(1 for r in rows if not r["measured"])
    fulls = sum(1 for r in rows if r["measured"] and r["df"] == BPS)
    top = max((r["bal"] for r in rows if r["measured"]), default=0)

    D = 10 ** vol_dec
    return {
        "label": label, "unit": unit, "blocks": [blocks[0], blocks[-1]],
        "total_addr": total_addr, "total_swaps": total_swaps, "total_vol": total_vol / D,
        "qual": len(qual), "qual_pct": 100 * len(qual) / max(total_addr, 1),
        "q_swaps": q_swaps, "q_swaps_pct": 100 * q_swaps / max(total_swaps, 1),
        "q_vol_pct": 100 * q_vol / max(total_vol, 1),
        "vw": vw, "sw": sw, "fulls": fulls, "top": top,
        "bands": {k: 100 * v / max(total_vol, 1) for k, v in bands.items()},
        "low_one_sided_pct": 100 * low_one_sided / max(total_vol, 1),
        "low_unmeasured_pct": 100 * low_unmeasured / max(total_vol, 1),
        "n_one_sided": n_one_sided, "n_unmeasured": n_unmeasured,
        "median_swap": sorted(s for r in rows for s in [])  # unused
    }


def show(r):
    print("=" * 72)
    print(r["label"])
    print("  blocks %d..%d   swaps %d   distinct addresses %d   volume %,.0f %s"
          .replace("%,.0f", "{:,.0f}").format(r["total_vol"])
          % (r["blocks"][0], r["blocks"][1], r["total_swaps"], r["total_addr"], r["unit"])
          if False else
          "  blocks {}..{}   swaps {:,}   distinct {:,}   volume {:,.0f} {}".format(
              r["blocks"][0], r["blocks"][1], r["total_swaps"], r["total_addr"],
              r["total_vol"], r["unit"]))
    print("  clear N=20            : {} ({:.1f}% of addresses)".format(r["qual"], r["qual_pct"]))
    print("  their share of swaps  : {:.1f}%".format(r["q_swaps_pct"]))
    print("  their share of volume : {:.1f}%".format(r["q_vol_pct"]))
    print("  vol-weighted mean depth : {:.0f} bps ({:.1f}%)".format(r["vw"], r["vw"] / 100))
    print("  swap-weighted mean depth: {:.0f} bps ({:.1f}%)".format(r["sw"], r["sw"] / 100))
    print("  at full depth: {} of {}   highest standing observed: {} bps".format(
        r["fulls"], r["qual"], r["top"]))
    print("  balance bands, share of volume:")
    for k, v in r["bands"].items():
        print("    {:5d}-{:5d} bps  {:6.1f}%  {}".format(k, k + 1999, v, "#" * int(v / 2)))
    print("  low band decomposition (0-1999 bps = {:.1f}% of volume):".format(r["bands"][0]))
    print("    measured, one-sided        : {:.1f}% of volume  ({} addresses)".format(
        r["low_one_sided_pct"], r["n_one_sided"]))
    print("    too little history to measure: {:.1f}% of volume  ({} addresses)".format(
        r["low_unmeasured_pct"], r["n_unmeasured"]))
    print()


if __name__ == "__main__":
    out = []
    for spec in sys.argv[1:]:
        path, label, leg, dec, unit = spec.split("|")
        r = analyse(path, label, int(leg), int(dec), unit)
        show(r); out.append(r)
    json.dump(out, io.open("replay2_summary.json", "w"), indent=1, default=str)
