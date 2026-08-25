# Pinned proving range

**Decided 2026-08-25. Pinned so it cannot be rediscovered under pressure on Sep 1.**

## The limitation, precisely

`brevis-sdk v0.3.12` cannot build receipt proofs against blocks containing **EIP-7702 (type 4)**
transactions. Building the receipts trie requires decoding every transaction in the block, and the
SDK's leaf-hash code rejects that type with `transaction type not supported`.

This was measured, not assumed:

| range | tx types present | type-4 count | SDK |
|---|---|---|---|
| 25,832,018 – 25,832,022 (current) | 0, 2, 3, **4** | **12** | fails |
| 21,146,234 – 21,146,238 (pinned) | 0, 1, 2, 3 | **0** | works |

**Blob transactions (type 3) are NOT the problem** — they appear in the working range too. The
culprit is specifically type 4, introduced by Pectra. An earlier note in this repo guessed
"blob/7702"; the measurement narrows it to 7702 alone.

## The pin

```
PROVING_BLOCK_ANCHOR = 21146236
```

Chosen because a proof was already generated and verified against it during the T1a gate, so it is
known-good by demonstration rather than by inspection. Any demo range must sit before Pectra.

## Disclosure

This is a sponsor-side limitation and gets stated plainly in the README and on camera:

> Proofs are generated against a historical block range. The Brevis SDK version available during
> the build window cannot parse EIP-7702 transactions, which appear in current mainnet blocks.

Honestly disclosed this costs nothing — deployment is not required by the rules, and a judge does
not penalise a dependency limitation. Hidden and then noticed, it costs Functionality, which is
graded against our own stated scope.
