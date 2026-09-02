# Product demo — shot by shot

**This is the full walkthrough, recorded live: landing → app → wallet → swap → the caps binding →
the integrations underneath.** Target 8–10 minutes. Not the submission video — that is
`video-script.md`, ≤5:00, cut from this footage plus the Foundry demo.

**Wallet confirmations stay in.** A signature popup and a pending spinner are what make it a product
rather than a slide deck. Shot 6 is built around one deliberately.

---

## Pre-flight — do all of this before the first frame

| | check |
|---|---|
| ☐ | `bash scripts/demo.sh` → **19 passed, 0 failed**. If anything is red, fix it before recording. |
| ☐ | MetaMask on **Sepolia**, using the operator address `0xBCA6…66Fe` (it holds standing 9,375 and 3,000,000 tETH) |
| ☐ | Sepolia ETH for gas — a swap is ~0.001 |
| ☐ | **Approve the router once, off-camera.** The first swap otherwise needs two popups and the story stutters. Do a 1,000 tETH swap now to prime it. |
| ☐ | Browser zoom **125%** — default text is too small to read in a recording |
| ☐ | Close every other tab. Bookmarks bar off. No notifications. |
| ☐ | Terminal: dark, large font, `cd` to the repo, window ~100 cols |
| ☐ | Tabs open in order: landing · app · Etherscan hook page |
| ☐ | If demoing the ZK proof live: prover already running and warm (`cd brevis/prover && go run ./cmd/main.go`) |

**Numbers you will say out loud** — all live on Sepolia right now:

| | |
|---|---|
| standing | 9,375 bps |
| depth fraction | 94.06% |
| tranche | 250,000 tETH |
| allowance | 235,150 tETH |
| base depth | 12,500 tETH |
| hook | `0x8878dbEB…6D0080` |

---

## Shot 1 · Landing — 0:00–0:40

**Screen:** https://manuel-dev01.github.io/tenure-hook/ · full screen, top of page.

**Do:** hold still 3 seconds. Let "Same fee. Earned depth." land before speaking.

> Tenure is a Uniswap v4 hook. Every address pays the same fee — that part never changes. What you
> earn is how much of the book you can take in a single transaction.

**Do:** scroll slowly to the standing axis.

> This is one real address: 9,375 basis points of directional balance. Seventeen buys, fifteen
> sells, across thirty-two real mainnet swaps. A ZK circuit proved that — it isn't a score we
> assigned.

**Do:** scroll to the five numbered steps, then to the disclosure block.

> And this is the part most demos leave out. The hook and registry are live on Sepolia, the circuit
> proves standing locally — but Brevis' on-chain delivery is retired, so no proof has landed on a
> chain. Standing here is operator-written, and the page says so before you ask.

---

## Shot 2 · Open the app — 0:40–1:10

**Do:** click **Open the app**.

> Same design, live contracts.

**Do:** point at the dark banner.

> That banner is the same disclosure, on every screen. The demo script actually fails if it ever
> disappears — an app implying a ZK delivery that hasn't happened is the one bug I'd never want to
> ship.

**Do:** click **Connect**. Approve in MetaMask. Let the popup be visible.

> Sepolia, my own wallet, nothing pre-loaded.

---

## Shot 3 · Standing — 1:10–2:10

**Screen:** Standing tab, now populated.

> 9,375 basis points, read live from the registry the hook actually consults.

**Do:** point at the tick on the 0–10,000 axis, then the four cells.

> Thirty-two swaps observed. Minimum sample is twenty — below that, standing is *undefined*, not
> zero, and undefined means base depth rather than exclusion.
>
> Thirty-two is also the circuit's whole receipt budget, which is why you'll never see a number like
> four hundred here.

**Do:** point at **Accessible depth 94.06%**.

> That's what the standing converts to: 94% of this pool's tranche, in one transaction.

**Do:** read the definition line aloud.

> Two times the smaller side, over the total. Counts only. No price, no oracle, no model. It is not
> a reputation score, and it can't be — there's nothing in it to be subjective about.

---

## Shot 4 · The order, and the credential — 2:10–3:00

**Do:** click **Swap**. Type **100000**.

> A hundred thousand, comfortably inside my allowance of 235,150.

**Do:** point at the credential panel.

> This is what I present to the pool. Bound to this router, this pool, this size, single-use,
> with a deadline. EIP-712 — I sign it, I hold it, the pool reads it.
>
> Bound to the router specifically, because the hook never sees my address. It sees whoever opened
> the lock. A router could claim to be anyone; a signature can't.

---

## Shot 5 · Execute — 3:00–4:00

**Do:** click **Execute swap**. **Let the MetaMask signature popup fill the frame.**

> That's the credential. No gas — it's a signature.

**Do:** approve. Then the transaction popup appears. **Let it sit.**

> And that's the swap itself.

**Do:** confirm. Wait for the pending spinner. **Do not cut the wait.**

> Real network, real confirmation.

**Do:** when it lands, point at the green panel and the updated balance.

> Filled. The fee I paid is the pool's 0.30% — the same 0.30% every address pays.

---

## Shot 6 · The cap binds — 4:00–5:00

**Do:** change the amount to **300000**. Click **Execute swap**. Sign.

> Three hundred thousand, against an allowance of 235,150.

**Do:** let the constraint panel appear.

> Rejected — and it names the reason. `ExceedsDepthAllowance`: it wanted 300,000 of depth, 235,150
> was available. That's the hook's own error, quoting its own numbers.
>
> No transaction was sent. The app simulates first, so a rejection costs nothing.

---

## Shot 7 · Splitting doesn't work — 5:00–6:00

**Do:** keep 300000. Tick **split into 2**. Execute. Sign both credentials.

> Same size, now split into two legs of 150,000 in one transaction. Each leg is under the cap. Under
> a per-swap limit this is the obvious way through.

**Do:** let the panel appear.

> Different error. `DepthExhaustedThisTx` — the first leg consumed 150,000, and the second one has
> 85,150 left. Depth is metered per transaction, in transient storage, keyed to the recovered
> signer. Signing more credentials cannot raise the ceiling.

**Say it plainly:**

> Two different errors from the same 300,000. That's the difference between a cap and a meter.

---

## Shot 8 · Nobody is excluded — 6:00–6:40

**Do:** set amount to **5000**. Click **Swap unsigned**.

> No credential at all. No signature.

**Do:** confirm, let it land.

> It executes. Zero standing still reaches 5% of the tranche — 12,500 here.
>
> That's deliberate. Anonymous swaps are metered too. If they weren't, the cheapest route to the
> whole book would be to sign nothing and split, and the mechanism would run backwards.

---

## Shot 9 · Underneath — the contracts — 6:40–7:40

**Screen:** Etherscan, the hook address.

> The hook, on Sepolia. Look at the last four characters: `0080`.

**Do:** highlight them.

> That's the permission bitmap, mined into the address with CREATE2. `beforeSwap` and nothing else.
> No `BEFORE_SWAP_RETURNS_DELTA`. The hook cannot alter execution economics — not "chooses not to",
> *cannot*, whatever code it contains. Fee parity is enforced by the address itself.

**Screen:** terminal.

```bash
forge script scripts/VerifyDemo.s.sol --rpc-url $RPC_URL
```

> Four assertions against those deployed contracts. Inside the allowance fills. Over it reverts.
> Split reverts. Unsigned executes at base depth.
>
> Each matched by the specific error selector — not by "something reverted". A swap can fail for a
> dozen reasons that have nothing to do with depth, and a check that only tested for failure would
> pass for all of them.

---

## Shot 10 · Underneath — the proof — 7:40–8:40

**Screen:** terminal.

```bash
cd brevis/app && npm run prove -- balanced
```

> The circuit, over real mainnet swap logs.

**While it runs (~1–3 min — cut the dead time in edit):**

> It's reading thirty-two real Uniswap Swap events and proving one thing: directional balance. The
> expected figure was computed from the raw logs, not by the circuit — and the script exits non-zero
> if they disagree. So this is a check, not a printout.

**When it completes:**

> 9,375 basis points, matching the figure computed independently. That's the number you saw in the
> app, and it's the number the pool acted on.

**Then, without being asked:**

> What doesn't work: getting that proof delivered on-chain. Brevis' aggregation service is retired.
> We paid the fee on Sepolia, the query reached `QS_PAID`, and it never moved. So standing in the
> app is operator-written — transcribing a figure the circuit really proved, but through the
> operator path, and the app says so in a banner.

---

## Shot 11 · Close — 8:40–9:00

**Screen:** back to the landing page.

> Same fee for everyone. What you earn is depth. The cap binds, it can't be split around, and nobody
> is turned away.
>
> Depth is the product.

---

## If something goes wrong on camera

| symptom | do this |
|---|---|
| MetaMask asks to approve the router | you skipped pre-flight. Approve, say "one-time token approval", carry on — it is normal and honest |
| Transaction stuck pending | keep talking over it; Sepolia is occasionally slow. Cut the wait in edit, never fake the result |
| RPC read errors in the app | public endpoint rate-limited. Reload. Have a second RPC ready |
| Wrong network | the app offers to switch — let that be visible, it is a real feature |
| A revert you didn't plan | **read it out and keep going.** The panel names the actual constraint. An unscripted correct error is better evidence than a scripted success |

## After recording

- [ ] Every wallet popup left in — that is the point
- [ ] No private key, seed phrase, or unrelated balance visible in any frame
- [ ] The disclosure said out loud at least twice (shots 1 and 10)
- [ ] Nothing claimed about Brevis beyond `video-script.md` §0
- [ ] Cut the ≤5:00 submission video from this footage
