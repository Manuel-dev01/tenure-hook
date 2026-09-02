# TENURE — demo video script

**Hard cap 5:00. Target 4:45. Your own voice — AI narration is a binary gate failure.**

Rewritten 2026-09-02 after the Sepolia deployment. Two earlier drafts said things about Brevis that
turned out to be false; **§0 is the current truth and supersedes anything you remember.**

---

## What to capture before the camera is on

| source | use for | note |
|---|---|---|
| `forge script scripts/Demo.s.sol` | cold open, split beat | Deterministic, no network. Pipe through `sed -n '/== Logs ==/,$p'` — the raw run prints trace noise and a `Gas used:` line above `== Logs ==`. |
| `forge script scripts/VerifyDemo.s.sol --rpc-url $RPC_URL` | the "it's live" beat | Runs against the **deployed** Sepolia contracts. Four lines, all four green. |
| the product recording (`recording-script.md`) | the "it's live" beat | A real swap through the app, wallet popups and all. Cut the shortest fragment showing one swap filling and one being capped. |

**Filmed out of logical order.** The demo runs proofs → depth → swap → split, which is the right
logical order and the wrong filmed order: the wow must land by 0:30, and it is *"same swap,
different outcome."* Open on demo beat **[3]** and backfill.

**On showing the app live.** Cut this beat from the full product recording
(`recording-script.md`), which swaps through the app for real — signature popup, confirmation and
all. Those confirmations are the evidence that it is a product; do not edit them out. For the ≤5:00
cut, use the shortest fragment that shows a swap filling and a swap being capped, and keep
`VerifyDemo` for the rigour, since it matches by error selector.

---

## §0 — the Brevis situation, stated correctly

Two earlier drafts were wrong about this, in opposite directions. Neither wording may survive:

- ~~"gateway submission was unavailable — Brevis-side outage"~~ — **false.** Blames a sponsor for
  our own bug.
- ~~"Brevis routes queries only for registered app circuits, and we didn't complete that step"~~ —
  **also false.** There is no registration step.

The real cause was ours: `brevis-sdk` was pinned five releases below their documented minimum, so
every query carried a stale constant the gateway had since rotated. Fixed.

**What is true now, and the only thing to say aloud:** the gateway accepts our proof, we paid the
fee on Sepolia, and the query reached `QS_PAID` — then stopped. It never reached `QS_PROOF_READY`,
which is Brevis' own aggregation step. Their appsdkv3 deployment appears retired: zero events in a
fortnight on Arbitrum, the one pair in their current docs. **So no proof has landed on any chain**,
and standing in the app is written by the operator registry instead.

If asked live, the short answer lands well:

> *"We had a stale dependency pin. We'd written two confident explanations for that failure before
> we ever traced it — both wrong. The real cause was greppable in our own dependency tree."*

---

## Two phrasings that would misstate a finding

### 1. "1.3% of that" parses as wrong

*"1.3% of that"* reads as 1.3% **of the 8.8%**, i.e. 0.11%. The real figure is 1.3% **of total
volume**, within the 8.8%. Use:

> Restraint falls on 8.8% of volume. Of that, one-sided flow is 1.3 points — the rest are addresses
> with too little history to be measured.

### 2. "below 500,000 … caps a fifth" understates our own cost

`analysis/mainnet-replay.md` measures a fifth (20.8%) **at** a 500,000 tranche. *Below* that it is
worse — 28.5% at 250,000, 42.5% at 100,000. Use:

> At a tranche of five hundred thousand USDC, base depth blocks about a fifth of long-tail swaps.
> Below that, more.

---

## Verified figures

| spoken | value | source |
|---|---|---|
| swap size, both traders | 60 units | demo beat [3] |
| trader A balance | 9,375 bps | demo beat [1] / proof |
| trader B balance | 0 bps | demo beat [1] / proof |
| accessible depth A / B / unsigned | 94 / 5 / 5 units | demo beat [2] |
| minimum sample | 20 swaps | `TenureRegistry.MIN_STANDING_SWAPS` |
| circuit receipt budget | 32 | `directional_balance.go:43` |
| base depth | 500 bps = 5% | `TenureHook.BASE_DEPTH_BPS` |
| addresses clearing N=20 | 52 of 906 (5.7%) | `analysis/mainnet-replay.md` |
| their share of volume | 92.3% | `analysis/mainnet-replay.md` |
| swaps replayed | 15,804 | `analysis/mainnet-replay.md` |
| volume-weighted mean depth | 6,721 bps | `analysis/mainnet-replay.md` |
| swap-weighted mean depth | 5,984 bps | `analysis/mainnet-replay.md` |
| restrained volume | 8.8%, of which 1.3 points one-sided | `analysis/mainnet-replay.md` |
| median long-tail swap | 3,563 USDC | `analysis/mainnet-replay.md` |
| tail blocked at 500k tranche | 20.8% | `analysis/mainnet-replay.md` |
| **Sepolia pool tranche** | **250,000** | `docs/deployments.json` |
| **live allowance at 9,375 bps** | **235,150** | `VerifyDemo` run |
| **live base depth** | **12,500** | `VerifyDemo` run |
| **hook address suffix** | **`0080`** | `beforeSwap` only, no return-delta bit |

---

## 0:00 – 0:25 — Cold open

**On screen:** demo beat [3] only. Nothing before it.

> Two traders. Same pool, same fee tier, same swap size — sixty units.
>
> One fills. One is capped.
>
> The fee was identical for both. What differed was how much of the book each could reach.

*(pause on CAPPED for two full seconds)*

> This is Tenure. Depth is the product.

**The pause is load-bearing.** Silence reads as confidence and gives the judge a beat to register
that the fee was identical. Most submissions talk continuously for five minutes and none of it
lands.

---

## 0:25 – 0:55 — Fee parity, and why it's structural

**On screen:** `test_FeeParity_HookHoldsNoFeePermission` passing, then the mined address bits.

> Every address pays the same fee. That isn't a policy we chose to follow — the hook's address is
> mined without the `BEFORE_SWAP_RETURNS_DELTA` permission bit, so it has no ability to alter
> execution economics at all.
>
> The hook doesn't decline to change your fee. It can't. The deployed address ends in double-oh-
> eight-oh, and you can check that yourself.

---

## 0:55 – 1:40 — Where standing comes from

**On screen:** demo beat [1], then the two fixtures.

> Standing comes from proven trading history. A Brevis ZK circuit reads real mainnet swap logs and
> proves one thing: directional balance — what fraction of your swaps went each way.
>
> Trader A, seventeen buys and fifteen sells: 9,375 basis points. Trader B, twenty-nine buys and
> zero sells: zero.
>
> We don't infer toxicity. We don't look at price, or at what happened after your trade. We count
> directions that already happened.
>
> Standing requires at least twenty swaps. That number was solved for, not picked — below twenty, a
> single additional trade moves the metric more than the depth curve can resolve. The derivation is
> in the repo, written before we ran any numbers.

---

## 1:40 – 2:10 — The split attack

**On screen:** demo beat [4].

> The obvious attack: sign several credentials, split one large swap into cap-sized pieces in a
> single transaction.
>
> It reverts. Depth is metered per transaction, not per swap, using transient storage — so
> splitting buys nothing.
>
> Anonymous swaps are metered too. Exempting them would have made signing strictly worse than not
> signing, and the whole mechanism would run backwards.

---

## 2:10 – 2:50 — It's live, and the cap binds on-chain

**On screen:** the app reading standing and allowance, then the four `VerifyDemo` lines.

**This beat is new and it is the strongest evidence in the video.** Do not rush it.

> This isn't a local demo. The hook, a router and a pool are deployed on Sepolia, and there's a
> front end you can open and connect a wallet to.
>
> A script asserts four things against those deployed contracts. A swap inside the allowance fills.
> A swap over it reverts. Two legs in one transaction accumulate, and the second one reverts. And an
> unsigned swap still executes, at base depth.
>
> Each is matched by the specific error the hook raises — not by "something reverted". A swap can
> fail for a dozen reasons that have nothing to do with depth, and a test that only checked for
> failure would pass for every one of them.

---

## 2:50 – 3:30 — How this compares

**On screen:** a still, no terminal.

This is the **Original Idea** criterion — 30%, the largest weight — answered aloud. Don't rush it.

> Most approaches to this problem move the price. Dynamic fees, directional fees, MEV auctions —
> they all decide what you pay.
>
> Tenure changes nothing about price. It changes how much of the book a single atomic transaction
> can reach.
>
> That distinction matters, because a fee is a cost you can pay to keep extracting. A depth ceiling
> isn't. And unlike a permissioned pool, nobody is excluded — zero standing still reaches five
> percent of the tranche, and standing is permissionless to earn.
>
> We're aware of one adjacent idea in this space: loyalty-based fee discounts. This is the opposite.
> The fee never moves.

**Tone on the last line.** That idea is published under Anirudh Pai of Dragonfly, who may be on the
panel. Deliver it **neutrally, as a distinction**, never as criticism.

---

## 3:30 – 4:05 — Evidence on real traffic

**On screen:** the distribution chart.

> We replayed real mainnet traffic on this pool. Fifty-two of nine hundred and six addresses clear
> the twenty-swap threshold — and those fifty-two are ninety-two percent of volume.
>
> Volume-weighted mean accessible depth: 6,721 basis points. Swap-weighted: 5,984.
>
> The average dollar moves at two-thirds of the tranche. The average address sits near the floor.
> Depth tracks proven behaviour, not headcount.

---

## 4:05 – 4:40 — What it costs, and what we don't claim

**On screen:** the 8.8% decomposition table.

**Deliver this at the same pace as the evidence section. Do not apologise.** Flat delivery reads as
rigour; hedged delivery reads as weakness. You are likely the only entrant who declines to claim a
benefit, and this is the beat most likely to be repeated in the judging room.

> Restraint falls on 8.8% of volume. Of that, one-sided flow is 1.3 points — the rest are addresses
> with too little history to be measured. That's the price of requiring evidence before granting
> depth, and an operator who sets the tranche too low makes it worse: at a tranche of five hundred
> thousand USDC, base depth blocks about a fifth of long-tail swaps. Below that, more.
>
> We do not claim this improves LP outcome. A closed simulation can't know where price goes after
> informed flow, and any reference price we picked would determine the sign of the result. The
> sensitivity is published instead.
>
> And the ZK path isn't fully live. The circuit proves standing, and the proof verifies — but
> Brevis' on-chain delivery is retired, so no proof has landed on a chain. Standing in the app is
> operator-written, and the app says so in a banner rather than letting you find out.

---

## 4:40 – 4:55 — Close

**On screen:** the demo's final two lines.

> The cap binds. It can't be split around. The fee never moved.
>
> Depth is the product.

---

## Timing — measured, not estimated

**715 spoken words**, counted from the quoted blocks in the timed beats:

```
python - <<'EOF'
import re
s=open('analysis/video-script.md',encoding='utf-8').read()
b=s[s.index('## 0:00'):s.index('## Timing')]
print(len(' '.join(l[2:] for l in b.split('\n') if l.startswith('> ')).split()))
EOF
```

| pace | runtime |
|---|---|
| 140 wpm (deliberate) | **5:06 — OVER THE CAP** |
| 150 wpm (normal technical) | **4:46** |
| 160 wpm (brisk) | 4:28 |

Plus the two-second pause at 0:22 and whatever the on-screen beats need.

**The Sepolia beat consumed the margin.** At the deliberate pace this script no longer fits, and
recording long fails a binary gate. Two options:

**1. Record at 150 wpm.** Ordinary technical delivery, not rushed. 4:46 leaves ~14 seconds for the
pause and the beat transitions. Viable, but there is no room for a slow sentence.

**2. Cut 47 words and keep 140 wpm** → 4:46 with the same headroom, delivered more slowly. The four
passages below are the most expendable in the script; each is a line the repo already makes in
writing:

| beat | cut | words |
|---|---|---|
| 0:25 | *"The deployed address ends in double-oh-eight-oh, and you can check that yourself."* | 12 |
| 0:55 | *"The derivation is in the repo, written before we ran any numbers."* | 12 |
| 2:50 | *"We're aware of one adjacent idea… The fee never moves."* | 20 |
| 3:30 | *"Swap-weighted: 5,984."* | 3 |

Cutting the 2:50 line is the only one with a real cost: it pre-empts the loyalty-pricing collapse
out loud rather than hoping nobody makes the connection. Cut the other three first.

**Do not cut the limitations beat.** It is the credibility of the whole submission, and it is the
passage most likely to be repeated in the judging room.

Do not spend any recovered margin adding content.

## Recording notes

- **Record twice minimum.** The first take finds the two or three sentences you can't say out loud.
- The margin against 5:00 is deliberate. **Recording long fails a binary gate.**
- Rehearse three answers: *why not a fee dial*, *why not a whitelist*, *why this metric*.

## Before you upload

- [ ] Length under 5:00 — **check the file, not your memory**
- [ ] Your own voice throughout, no AI narration
- [ ] Every number spoken re-derived from its artifact, not from the README
- [ ] Nothing said about Brevis beyond §0
- [ ] The app fragment shows a real swap — the wallet confirmations are the evidence, not noise
- [ ] Plays logged-out
- [ ] Repo link points to `main`
