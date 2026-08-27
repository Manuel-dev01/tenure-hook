# One-liner collision check against the UHI Hook Directory

**Date:** 2026-08-25 · **Verdict: the wedge is clear, and the fee-parity constraint is now
evidenced rather than assumed.**

The one-liner under test:

> **Depth is the product. Every address pays the same fee; what you earn is how much of the book
> you can reach.**

## Method

`hooks.atrium.academy` redirects to a Notion page that renders client-side, so it cannot be read by
fetching HTML. The page itself links a maintained export:
[`AtriumAcademy/UHI-Hook-Data`](https://github.com/AtriumAcademy/UHI-Hook-Data) →
`hook_directory.csv`.

**660 projects** across all cohorts, with name, description, tags, cohort, and integrations.
Searched for every term in the collision space: loyalty, reward, reputation, standing, credential,
tier, discount, rebate, size limit, max swap size, depth, tranche, gated liquidity, KYC, allowlist,
and ZK-proof-of-history.

## The result that matters

**Nobody gates swap size on proven trading history.**

Cross-searching for projects mentioning *both* size/depth *and* history/reputation returned 11
hits, and **none of them is the mechanism**. They are TWAMM execution-splitting, FHE-encrypted
limit orders, on-chain limit orders, launch-liquidity locks, and five separate senior/junior LP
tranche products. "Tranche" in this directory always means *splitting LP risk*, never *reserving
depth for a trader*.

Direct search for size caps returned only 2 hits, neither related: `FlexFee` (dynamic fees from
volatility and swap size) and `Autonomous OTC Hook` (a separate execution lane for large trades).

## The precedents that are close, and what they mean

| Project | Cohort | What it does | Relation |
|---|---|---|---|
| **Loyalty Points Fee Hook** | UHI3 | "discount on swap fees based on swap volume" — tags: *Dynamic Fee, Trading Rewards* | **The exact pattern we guard against, already built.** Differs from Tenure on the one axis that matters: it moves the fee. |
| **SwapNFT** | — | mints a soulbound **tier** NFT based on price impact, then applies a **fee discount** | history → tier → fee. Also the banned pattern, and it uses the banned vocabulary. |
| **Reputation Hook - MetaPools** | UHI2 | "giving identities to traders globally" — integrations include **Brevis** | Brevis + trader reputation has a precedent. Our ZK layer is not itself novel. |
| KYC / allowlist gating | many | 40 hits — `kvhook`, `RWAMarket`, `DCLEX`, `Compliant DEX`, `ZK Proof-of-Compliance` | The "whitelist with extra steps" objection is a pattern judges have seen repeatedly. |

## What this changes

1. **The fee-parity rule is not paranoia.** Fee-discount-on-history exists in this directory at least twice. If
   Tenure is heard as loyalty pricing, a judge is not imagining a competitor — they are recalling a
   specific prior project. Leading with depth is the *only* thing separating us from
   `Loyalty Points Fee Hook` in a judge's memory, and it is not optional.

2. **`tier` must never appear.** `SwapNFT` occupies that word with a fee discount attached.

3. **Brevis is not the differentiator.** Brevis appears across multiple projects including a trader
   reputation hook. The novelty claim must rest entirely on *the entitlement being depth rather
   than price*, never on "we used ZK".

4. **Say the non-exclusion property out loud.** With 40 KYC/allowlist projects in the directory,
   the whitelist objection arrives pre-loaded. That an address with zero standing still receives a
   non-zero depth allowance — asserted in `test_T2_StandingChangesDepthOnly` — is the rebuttal, and
   it should be stated on camera, not left to be inferred.

## Verdict

The one-liner survives. No prior project sells depth as the entitlement. The surrounding space is
crowded enough that the fee-parity discipline is load-bearing rather than stylistic.
