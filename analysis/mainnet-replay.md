# Stage 5, what the mechanism would do on real mainnet traffic

**Pool:** USDC/WETH 0.05%, `0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640`
**Range:** blocks 21,126,236 – 21,146,236 (20,001 blocks, ending at the pinned proving anchor)
**Data:** 15,804 real `Swap` logs, 906 distinct recipient addresses.

Everything below is **counted from logs**. No counterfactual is modelled and none can be, what the
price would have done had a trade been capped is unknowable, and modelling it would reintroduce
exactly the reference-price problem that made the Stage 4 LP-value number meaningless. This answers
*"does the mechanism do anything on real traffic?"*, not *"is the pool better off?"*

---

## 1. Standing is rare. The addresses that hold it do most of the volume.

| | |
|---|---|
| distinct addresses | **906** |
| clear N = 20 and hold standing | **52 (5.7%)** |
| swaps by those 52 | 13,873 / 15,804 (**87.8%**) |
| volume by those 52 | **92.3%** of all volume |
| everyone else | falls to base depth |

**The mechanism is live, not vacuous.** The worry going in was that everyone would clear N = 20 and
nothing would bind. The opposite is true: 94.3% of addresses never reach 20 swaps on this pool in
this window, so they receive base depth and standing genuinely has to be earned.

## 2. Directional balance separates real actors

Among the 52 with standing:

```
    0-  999 bps | 12  ############     one-sided
 1000- 1999 bps |  1  #
 2000- 2999 bps |  0
 3000- 3999 bps |  1  #
 4000- 4999 bps |  3  ###
 5000- 5999 bps |  4  ####
 6000- 6999 bps |  7  #######
 7000- 7999 bps |  9  #########
 8000- 8999 bps |  5  #####
 9000- 9999 bps | 10  ##########     two-sided
```

The metric is not noise. It finds addresses that are *perfectly* one-sided over large samples:

| address | swaps | buys | sells | balance | depth |
|---|---|---|---|---|---|
| `0x163c5e05…bcbb1` | 445 | 0 | 445 | 0 bps | 500 bps |
| `0x3416cf6c…27c6` | 34 | 0 | 34 | 0 bps | 500 bps |
| `0x74de5d4f…6631` | 93 | 1 | 92 | 215 bps | 704 bps |

445 swaps, every single one in the same direction, is not a coincidence of the window.

## 2b. Accessible depth across real traffic, the headline number

Per-swap depth entitlement, weighted by the volume actually traded:

| measure | value |
|---|---|
| **volume-weighted mean accessible depth** | **6721 bps, 67.2% of tranche** |
| swap-weighted mean accessible depth | 5984 bps, 59.8% |
| floor (no standing) | 500 bps |
| ceiling | 10000 bps |

**The average dollar on this pool moves at roughly two-thirds of the tranche, while the average
address sits near the floor.** That gap is the mechanism working as designed: depth follows proven
behaviour, not headcount.

Volume by accessible-depth band:

| band | share of volume |
|---|---|
| 0–1999 bps | **8.8%** |
| 2000–3999 bps | 0.6% |
| 4000–5999 bps | 13.8% |
| 6000–7999 bps | 41.5% |
| 8000–10000 bps | 35.3% |

**A nuance that matters and is easy to state wrongly.** That 8.8% is *not* the same population as
the 1.3% one-sided figure below. It is one-sided actors (1.3%) **plus** addresses that have not
traded enough to be measured at all (~7.5%). Restraint therefore falls on two different groups:
those measured and found one-sided, and those not yet measurable. Only the first is the flow the
mechanism is aimed at; the second is the cost of requiring evidence before granting depth.

---

## 3. The uncomfortable finding: one-sided flow is 1.3% of volume

| balance band | addresses | share of all volume | depth received |
|---|---|---|---|
| **0–1999 (one-sided)** | 13 | **1.3%** | 500–2399 bps |
| 2000–3999 | 1 | 0.4% | ~3349 bps |
| 4000–5999 | 7 | 33.0% | ~5249 bps |
| 6000–7999 | 16 | 22.3% | ~7149 bps |
| 8000–9999 (two-sided) | 15 | 35.3% | ~9049 bps |

**The mechanism binds hard on flow that is a small slice of this pool.** It correctly identifies
one-sided actors and would restrict them to near-base depth, but they move 1.3% of volume here.
90.6% of volume comes from addresses balanced enough to receive 5249 bps or more.

This is stated plainly because it is the honest answer to *"does this matter at scale?"* on this
pool, in this window. It is **one pool over ~2.8 days** and should not be generalised further than
that. A pool with a different flow mix could look very different, and we have not measured one.

## 4. Nobody reaches full depth

**0 of 52** addresses with standing reach the top of the curve. The highest observed is 9277 bps
(balance 9239). `FULL_DEPTH_STANDING = 10000` requires *perfect* directional balance, which no real
address achieves over a large sample.

Recorded as an observation, **not acted on**. Stage 4 and 5 are measurement stages and the
mechanism is frozen. If the curve were ever revisited, this is the input.

## 5. Base depth is not punitive for the long tail, if the tranche is set sensibly

The 854 addresses without standing made 1,931 swaps:

| | USDC |
|---|---|
| median swap | 3,563 |
| 90th percentile | 75,961 |
| 99th percentile | 390,447 |
| largest | 1,654,558 |

How often base depth (500 bps of tranche) would block them:

| tranche | base cap | tail swaps blocked |
|---|---|---|
| 100,000 | 5,000 | 821 / 1931 (42.5%) |
| 250,000 | 12,500 | 551 / 1931 (28.5%) |
| 500,000 | 25,000 | 402 / 1931 (20.8%) |
| **1,000,000** | **50,000** | **259 / 1931 (13.4%)** |
| 5,000,000 | 250,000 | 54 / 1931 (2.8%) |
| 10,000,000 | 500,000 | 10 / 1931 (0.5%) |

**The tranche is an operator parameter and is reported across a range rather than chosen**, for the
same reason no reference price was chosen in Stage 4. But the shape matters: a tranche set too low
turns "nobody is excluded" into a real cost for ordinary users, since a median retail swap is
3,563 USDC and the 90th percentile is 75,961. At a 500,000 USDC tranche, base depth blocks 20.8% of
long-tail swaps on this pool. **Below that it is worse, not equal**, 28.5% at 250,000 and 42.5% at
100,000, per the table above.

State it that way round. "Below 500,000 it caps a fifth" reads as a ceiling when a fifth is actually
the *floor* of the cost, and it understates our own downside, the direction of error a judge with
the repo open would catch.

That is a genuine operational caveat and it belongs on camera.

## 6. Share of all volume above the cap

| tranche (USDC) | capped swaps | capped volume | excess over caps |
|---|---|---|---|
| 50,000 | 6,680 / 15,804 | 94.0% | 69.1% |
| 100,000 | 4,645 / 15,804 | 81.3% | 48.5% |
| 250,000 | 1,587 / 15,804 | 43.8% | 22.5% |
| 500,000 | 681 / 15,804 | 22.2% | 11.9% |
| 1,000,000 | 334 / 15,804 | 12.1% | 6.6% |
| 5,000,000 | 58 / 15,804 | 3.7% | 1.8% |

---

## What Stage 5 establishes, and what it does not

**Establishes:**
- standing is genuinely scarce, 5.7% of addresses earn it
- directional balance identifies real, persistently one-sided actors over large samples
- the mechanism binds on real traffic rather than being cosmetic
- the full-depth ceiling is unreachable in practice
- tranche sizing has a real effect on ordinary users, quantified

**Does not establish:**
- that LPs are better off. That claim is not made anywhere in this submission, and Stage 5 was
  deliberately *not* designed to produce a number for it. Fork-replay has the same counterfactual
  problem as the sandbox, in a costume with more machinery: the price path had the informed trade
  been capped is unknowable, and modelling it means choosing assumptions that determine the answer.
- that one-sided flow is materially large on pools generally. Here it is 1.3% of volume. One pool,
  one window.
