"""Collect Uniswap V3 Swap logs over the pinned proving range.

No counterfactual is computed here and none can be: this only counts what actually happened.
"""
import json, urllib.request, time, sys, io

RPC = "https://eth.drpc.org"
POOL = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"
SIG = "0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67"
HDR = {"Content-Type": "application/json", "User-Agent": "Mozilla/5.0 tenure-research"}

ANCHOR = 21146236
SPAN = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
CHUNK = 1000


def rpc(method, params, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(
                RPC, json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1}).encode(), HDR
            )
            d = json.load(urllib.request.urlopen(req, timeout=90))
            if "result" in d and d["result"] is not None:
                return d["result"]
        except Exception:
            pass
        time.sleep(2 + 3 * i)
    return None


logs = []
start = ANCHOR - SPAN
got_chunks = 0
for lo in range(start, ANCHOR + 1, CHUNK):
    hi = min(lo + CHUNK - 1, ANCHOR)
    r = rpc("eth_getLogs", [{"address": POOL, "topics": [SIG],
                             "fromBlock": hex(lo), "toBlock": hex(hi)}])
    if r is None:
        print(f"  chunk {lo}-{hi}: FAILED", flush=True)
        continue
    logs += r
    got_chunks += 1
    print(f"  chunk {lo}-{hi}: {len(r)} logs (total {len(logs)})", flush=True)

print(f"collected {len(logs)} logs over {SPAN} blocks from {got_chunks} chunks")
json.dump(logs, io.open("range_logs.json", "w"))
print("saved range_logs.json")
