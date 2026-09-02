# TENURE — demo video script

**Hard cap 5:00. Target 4:40. Your own voice — AI narration is a binary gate failure.**

Pipe the demo through `sed -n '/== Logs ==/,$p'` before recording. Decide this before the camera is
on — the raw run prints trace noise and a `Gas used:` line above `== Logs ==`.

**Filmed out of logical order.** The demo runs proofs → depth → swap → split. That is the right
logical order and the wrong filmed order: the wow moment must land by 0:30, and it is *"same swap,
different outcome."* So the video opens on beat **[3]** and backfills the machinery. Run the demo
once, capture the full output, then cut the sections out of order.

---

## Two corrections before recording

Every number below was re-derived from its artifact per `VERIFY.md`. All check out — but **two
phrasings would misstate the finding aloud.** Both are in the 3:50 section.

### 1. "1.3% of that" is ambiguous and reads as wrong

Draft: *"Restraint falls on 8.8% of volume — and only 1.3% of that is one-sided flow."*

*"1.3% of that"* parses as 1.3% **of the 8.8%**, i.e. 0.11%. The real figure is 1.3% **of total
volume**, out of the 8.8% total. Use:

> Restraint falls on 8.8% of volume. Of that, one-sided flow is 1.3 points — the rest are addresses
> with too little history to be measured.

### 2. "below about 500,000 USDC … caps a fifth" understates it

`analysis/mainnet-replay.md` measures a fifth (20.8%) **at** a 500,000 tranche. *Below* that it is
worse — 28.5% at 250,000, 42.5% at 100,000. Saying "below … a fifth" is wrong in the direction that
flatters us. Use:

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
| base depth | 500 bps = 5% | `TenureHook.BASE_DEPTH_BPS` |
| addresses clearing N=20 | 52 of 906 (5.7%) | `analysis/mainnet-replay.md` |
| their share of volume | 92.3% | `analysis/mainnet-replay.md` |
| swaps replayed | 15,804 | `analysis/mainnet-replay.md` |
| volume-weighted mean depth | 6,721 bps | `analysis/mainnet-replay.md` |
| swap-weighted mean depth | 5,984 bps | `analysis/mainnet-replay.md` |
| restrained volume | 8.8%, of which 1.3 points one-sided | `analysis/mainnet-replay.md` |
| median long-tail swap | 3,563 USDC | `analysis/mainnet-replay.md` |
| tail blocked at 500k tranche | 20.8% | `analysis/mainnet-replay.md` |

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

## 0:25 – 1:00 — Fee parity, and why it's structural

**On screen:** `test_FeeParity_HookHoldsNoFeePermission` passing, then the mined address bits.

> Every address pays the same fee. That isn't a policy we chose to follow — the hook's address is
> mined without the `BEFORE_SWAP_RETURNS_DELTA` permission bit, so it has no ability to alter
> execution economics at all.
>
> The hook doesn't decline to change your fee. It can't.

---

## 1:00 – 1:50 — Where standing comes from

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
> in the repo, written before we ran any numbers at any threshold.

---

## 1:50 – 2:20 — The split attack

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

## 2:20 – 3:05 — How this compares

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
panel. Naming it and drawing the contrast is right — it pre-empts the collapse rather than hoping
nobody makes it. Deliver it **neutrally, as a distinction**, never as criticism of a published idea.

---

## 3:05 – 3:50 — Evidence on real traffic

**On screen:** the distribution chart.

> We replayed real mainnet traffic on this pool. Fifty-two of nine hundred and six addresses clear
> the twenty-swap threshold — and those fifty-two are ninety-two percent of volume.
>
> Volume-weighted mean accessible depth: 6,721 basis points. Swap-weighted: 5,984.
>
> The average dollar moves at two-thirds of the tranche. The average address sits near the floor.
> Depth tracks proven behaviour, not headcount.

---

## 3:50 – 4:25 — What it costs, and what we don't claim

**On screen:** the 8.8% decomposition table.

**Deliver this at the same pace and tone as the evidence section. Do not apologise.** The content is
unusual enough that flat delivery reads as rigour; hedged delivery reads as weakness. You are likely
the only entrant who declines to claim a benefit, and this is the beat most likely to be repeated in
the judging room.

> Restraint falls on 8.8% of volume. Of that, one-sided flow is 1.3 points — the rest are addresses
> with too little history to be measured. Their only characteristic is being new. That's the price
> of requiring evidence before granting depth, and an operator who sets the tranche too low makes it
> worse: at a tranche of five hundred thousand USDC, base depth blocks about a fifth of long-tail
> swaps. Below that, more.
>
> We do not claim this improves LP outcome. A closed simulation can't know where price goes after
> informed flow, and any reference price we picked would determine the sign of the result. The
> sensitivity is published instead.
>
> Also disclosed: proofs are generated against a pre-Pectra block range, because the SDK can't parse
> EIP-7702 transactions. And gateway submission isn't wired — Brevis routes queries only for
> registered app circuits, and we didn't complete that step — so proofs are generated and verified
> locally instead.

---

## 4:25 – 4:40 — Close

**On screen:** demo's final two lines.

> The cap binds. It can't be split around. The fee never moved.
>
> Depth is the product.

---

## Timing — measured, not estimated

578 spoken words across all sections.

| pace | runtime |
|---|---|
| 140 wpm (deliberate) | **4:07** |
| 150 wpm (normal technical) | 3:51 |
| 160 wpm (brisk) | 3:36 |

Plus the two-second pause at 0:22 and whatever the on-screen beats need.

**You have more headroom than the 4:40 target suggests.** Spend it on the pause, on slowing the
comparison section at 2:20, and on not rushing the limitations at 3:50 — those are the two beats
where pace does the most work. Do not spend it adding content.

## Recording notes

- **Record twice minimum.** The first take finds the two or three sentences you can't say out loud.
  Re-read those, then take two.
- The 20-second margin against the 5:00 cap is deliberate. **Recording long fails a binary gate.**

## Before you upload

- [ ] Length under 5:00 — **check the file, not your memory**
- [ ] Your own voice throughout, no AI narration
- [ ] Every number spoken re-derived from the artifact, not copied from the README
- [ ] Plays logged-out
- [ ] Repo link points to `main`
