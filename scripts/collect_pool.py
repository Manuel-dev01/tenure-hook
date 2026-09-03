"""Collect V3 Swap logs for an arbitrary pool over the SAME pinned range as Stage 5."""
import json, urllib.request, time, sys, io
RPC="https://eth.drpc.org"
SIG="0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67"
HDR={"Content-Type":"application/json","User-Agent":"Mozilla/5.0 tenure-research"}
ANCHOR=21146236; SPAN=20000; CHUNK=1000
POOL=sys.argv[1]; OUT=sys.argv[2]
def rpc(m,p,tries=5):
    for i in range(tries):
        try:
            req=urllib.request.Request(RPC,json.dumps({"jsonrpc":"2.0","method":m,"params":p,"id":1}).encode(),HDR)
            d=json.load(urllib.request.urlopen(req,timeout=90))
            if d.get("result") is not None: return d["result"]
        except Exception: pass
        time.sleep(2+2*i)
    return None
logs=[]; ok=0; fail=0
for lo in range(ANCHOR-SPAN, ANCHOR+1, CHUNK):
    hi=min(lo+CHUNK-1,ANCHOR)
    r=rpc("eth_getLogs",[{"address":POOL,"topics":[SIG],"fromBlock":hex(lo),"toBlock":hex(hi)}])
    if r is None:
        fail+=1; print("  chunk %d-%d FAILED"%(lo,hi),flush=True); continue
    logs+=r; ok+=1
    print("  chunk %d-%d: %d logs (total %d)"%(lo,hi,len(r),len(logs)),flush=True)
print("collected %d logs, %d chunks ok, %d failed"%(len(logs),ok,fail))
if fail: print("WARNING: %d chunks failed; counts are INCOMPLETE"%fail)
json.dump(logs,io.open(OUT,"w"))
