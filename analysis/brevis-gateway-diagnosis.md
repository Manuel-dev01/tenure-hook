# The Brevis gateway: what was actually wrong

**2026-09-02. Resolved. The gateway accepts our circuit and the query reaches "awaiting payment".**

This file exists because the same failure was explained wrongly twice, and both wrong explanations
were written into the README, the video script and the submission checklist before anyone traced
the error. Recording the method, not just the answer.

---

## The error

```
failed to submit Not enough query info invalid app circuit chain 1
dummy input commitment 0x127d5d805cfd68acd5c88659d1cf96bcec545959ed27b8d654e90a8d9165501d
```

## Two wrong explanations, and why they were wrong

**1. "Brevis-side outage."** The first observed failure was an application-layer `RST_STREAM`
against the **upstream example circuit**. That is a different fault, possibly transient, and it was
conflated with the later rejection above into a single story about someone else's uptime. Nothing
was measured. This was the worst version: it blamed a sponsor, in writing, for our own bug, and a
Brevis engineer may be on the judging panel.

**2. "Our app circuit is not registered with Brevis."** Plausible-sounding and also false. There is
no registration step. Brevis document the partner key and callback address as **not required**;
both are empty strings in our submission and the query is accepted.

Both were explanations *invented to fit* an error message. Neither was traced.

## What it actually was

`0x127d5d80...` is not an identifier the gateway assigned to us. It is a **string constant in the
version of the SDK we pinned**:

```go
// brevis-sdk@v0.3.12/common/const.go:3
var DummyReceiptInputCommitment = map[uint64]string{
	1: "0x127d5d805cfd68acd5c88659d1cf96bcec545959ed27b8d654e90a8d9165501d",
```

Unused receipt slots in the circuit's fixed 32-slot budget are padded with this value, so it is
baked into the proof's public inputs. Asking the live gateway what it expects for chain 1
(`GetCircuitDummyInput`) returns something else entirely:

```
chain 1
  receipt 0x182b42857c3565a60237a9d9f8e98a90a542019aa317623c4ade5f3c0d8f44ad
  storage 0x181f2ba97b5602ecdcd9b21b644d91539f75a771cf77e9a2b5a54c7f0e43143f
  tx      0x0c17bfae2b03394f5e5e2f4386af9398d0f8e70dd340ec6e3285a595b66e7650
```

Brevis rotated these values and stopped hard-coding them: from v0.3.17 the SDK fetches them from
the gateway while building circuit input (`sdk/app.go`, `GetCircuitDummyInput`). Their docs state
the minimum plainly, *"Please make sure SDK version is no less than 0.3.17. It is not
backward-compatible."* We were on **0.3.12**, five releases below a documented floor.

**The whole failure was a stale dependency pin.** The gateway was telling us the exact value it
objected to, in every error message, from the first attempt.

### The lesson worth keeping

The difference between this diagnosis and the two before it is not effort or cleverness. It is that
the rejected value was **greppable in our own dependency tree** and **queryable from the service**.
Two commands settled what two rounds of reasoning got wrong. When an error message contains a
literal, find where the literal comes from before explaining the error.

---

## The upgrade: v0.3.12 to v0.3.33

Four things had to change. Nothing in the circuit, the hook or any contract.

| what | detail |
|---|---|
| `go.mod` require | `brevis-sdk v0.3.12` becomes `v0.3.33` |
| `go.mod` replace | v0.3.33 pins `gnark => brevis-network/gnark v0.1.0` and `go-ethereum => celer-network/go-ethereum v0.0.0-20250328211401`. **A replace directive in a dependency is ignored by the go tool**. Only the main module's replaces apply, so both must be restated in `brevis/prover/go.mod`. |
| prover API | `NewService` takes a third argument, `prover.SourceChainConfigs`; the source RPC moved out of `ServiceConfig`. `Serve` now takes `(host, grpcPort, restPort)`. |
| TS request | `ProofRequest.build()` in brevis-sdk-typescript 1.3.1 never sets `src_chain_id`. Harmless under v0.3.12, fatal under v0.3.33, which keys provers by chain and rejects 0 with `unsupported chain ID: 0`. Fixed by `src/chain_scoped_request.ts`, which overrides `build()`. |

The TypeScript SDK is stuck at **1.3.1** (Nov 2024) and has not tracked the Go SDK. It is still
usable: `PrepareQueryRequest` and `AppCircuitInfo` were diffed field-by-field between v0.3.12 and
v0.3.33 and are **identical**. The two fields v0.3.33 adds (`use_vm`, `vm_app_circuit_info`) are
optional and irrelevant to a non-VM app circuit. The corrected values ride in the prover's
`circuit_info`, which the TS client passes through untouched. So the Go-side bump is sufficient.

### What changed as a result

| | v0.3.12 | v0.3.33 |
|---|---|---|
| constraints | 1,583,108 | **1,601,003** |
| circuit digest | `0x871ee235…` | **`0x0d0d4ebe86cc9ec341bc9b98d94d52bc9b7bfbe67be97ae75a3e71e8f5cd8baa`** |
| vk hash | `0x028f783f…` | **`0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8`** |
| proving key | 134,252,200 bytes | 134,252,200 bytes |

**The vk hash changed, so the value `setVkHash` takes changed.** Deploying with the old one would
reject every real proof.

### Both fixtures re-proved, not assumed

| fixture | trader | buys / sells | expected | circuit output | swaps | attested window |
|---|---|---|---|---|---|---|
| balanced | `0x0f4a1d7f…77eca3` | 17 / 15 | 9375 bps | **9375 bps** | 32 | 21126338–21144863 |
| one-sided | `0x308c6fbd…d75e2a6` | 29 / 0 | 0 bps | **0 bps** | 29 | 21126236–21145773 |

Identical to the v0.3.12 results. A version bump that changed the numbers would have meant the
circuit's meaning moved; it did not.

44 Solidity tests still pass and `scripts/gate.sh` still reports GATE PASS. No contract changed.

---

## The gateway now accepts the query

```
step 1/2  proving locally...
          proved, vk hash 0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8
step 2/2  submitting to appsdkv3.brevis.network:443, destination chain 42161 ...
GATEWAY ACCEPTED THE QUERY
  queryKey: 0x5df2d4775e5cbbc38f71e7c70ee040d016f64551ef5cf5ba78b161643e8b42d6, nonce 1788326279553
  fee     : 0
```

Reproduce with `npm run gateway` (destination Arbitrum) or `npm run gateway -- 11155111`.

**That nonce is NOT the one that was paid.** The transcript above is a destination-42161 run. The
query actually paid for is a later destination-11155111 run of the same circuit and fixture, and its
nonce is **1788341943029**, read from the payment receipt rather than from a console scrollback:

```
$ cast receipt 0xd5f1a81ba9a7277525dd79ec353d30ea06248fdbcbda946f56826b6ae406fb47 --rpc-url $RPC
$ cast to-dec 0x000001a0617c7af5
1788341943029
```

The `query_hash` is the same in both, because it is a hash of the circuit and inputs; only the nonce
differs per submission. An earlier version of this file quoted nonce `1788326279553` here and let it
stand as the paid one, which was wrong. Confirmed by the gateway: querying nonce 1788341943029
against 42161 returns `code:1012 not found`, so the paid query only ever existed for Sepolia.

**Precision about what this does and does not show.** `PrepareQuery` accepting a query proves the
gateway will route this circuit. It does **not** prove Brevis will fulfil it on a given destination
chain, fulfilment happens after the fee is paid on-chain. Both 42161 and 11155111 are accepted at
this stage, which is evidence about routing only.

---

## The remaining step: paying and receiving the callback

Not done. It requires an on-chain transaction, so it is a deploy decision rather than a code one.

### Where things can land

| | Arbitrum One (42161) | Sepolia (11155111) |
|---|---|---|
| BrevisRequest | `0x91540fe35a245ba83459f6410c86f1aec309b290` | `0xa082F86d9d1660C29cf3f962A31d7D20E367154F` |
| contract live | yes (`brevisProof()` returns `0x0fEc0b24…`) | yes (`brevisProof()` returns `0x70cFEb37…`) |
| in current docs | **yes**, the one listed supported pair, mainnet to Arbitrum | no, and not on the legacy page either. See the correction below. |
| costs | real ETH | testnet ETH |

Both contracts are deployed and answer calls; their bytecode prefixes match. **Sepolia is therefore
worth attempting first: it is free, and failure costs nothing but time.** Its risk is that Brevis
may no longer run fulfilment workers for it, in which case the query is accepted, paid and never
fulfilled, which is itself a clean, publishable result.

### Exact sequence

1. Deploy `TenureRegistry(brevisRequest, operator)` with the BrevisRequest address for the chosen
   chain. The constructor already takes it (`src/TenureRegistry.sol:67`).
2. `setVkHash(0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8)`.
   **Not optional.** `expectedVkHash` starts at zero and every callback reverts until it is set;
   setting it wrong is worse than not deploying, because it would accept proofs from another
   circuit. This is the published audit finding the registry's natspec cites.
3. `npm run gateway -- <chainId>` and keep the `queryKey`, which is `(proofId, nonce)`.
4. Call `sendRequest` on BrevisRequest, paying the quoted fee as `msg.value`. Signature verified
   from the SDK's own generated bindings (`brevis-sdk@v0.3.33/sdk/eth/bindings.go:16092`):

   ```solidity
   function sendRequest(
       bytes32  _proofId,    // queryKey.query_hash
       uint64   _nonce,      // queryKey.nonce
       address  _refundee,   // your EOA
       Callback _callback,   // (address target, uint64 gas) = (TenureRegistry, gas limit)
       uint8    _option      // 0 = ZK mode
   ) payable;
   ```
5. Wait ~2 minutes. Brevis aggregates and calls `brevisCallback` on the registry, which validates
   `_vkHash` and records the standing. Poll with `queryRequestStatus(_proofId, _nonce)`.

Success is a `StandingRecorded` event carrying **0 bps over 29 swaps for
`0x308c6fbd6a14881af333649f17f2fde9cd75e2a6`**, the ONE-SIDED fixture. Not 9375, and not the
balanced fixture's address. The one-sided fixture was chosen for the paid submission because it
carries 29 receipts rather than 32 and was the cheaper of the two to prove. An earlier version of
this file named the balanced fixture here, which would have made anyone checking the chain look for
the wrong event on the wrong address.

### The fee is genuinely zero, settled, not assumed

The gateway quotes `fee` as a base-10 **string**, which the SDK parses into the `msg.value` for
`sendRequest` (`sdk/app.go:642`). That left two readings of an earlier `fee: 0` print: a real quote
of zero, or an unset proto field rendering as zero.

`npm run gateway` now prints the raw value and its type. The gateway returns `"0"`, a populated
string. An unset field would be `""`, and `new(big.Int).SetString("", 10)` fails, which is why the
SDK errors with `cannot parse fee value of` rather than defaulting. So `sendRequest` needs **no
`msg.value`**; only gas.

### Deployed to Sepolia, 2026-09-02

Live, verified by reading the chain rather than trusting the deploy log:

| | |
|---|---|
| TenureRegistry | `0x03F05F1c89b9725F2AD775Aed85F60DD38af19B5` |
| TenureHook | `0x8878dbEB12C6Aba4ab6629DB41238d131e6D0080` |
| `expectedVkHash()` | `0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8` |
| `brevisRequest()` | `0xa082F86d9d1660C29cf3f962A31d7D20E367154F` |
| deploy cost | ~0.0068 ETH at 2.1 gwei |

The hook address ends **`0080`**, `BEFORE_SWAP_FLAG` and nothing else. The fee-parity property is
enforced by the deployed address itself, not by the code inside it.

Payment: tx `0xd5f1a81ba9a7277525dd79ec353d30ea06248fdbcbda946f56826b6ae406fb47`, status 1,
`RequestSent` emitted with the registry as callback target, **fee 0**, callback gas 400,000.

#### Outcome: paid and accepted, not fulfilled

The gateway reports **`QS_PAID`** and is holding the finished circuit output:

```
0x308c6fbd6a14881af333649f17f2fde9cd75e2a6 0000 001d 0000000001425c5c 000000000142a8ad
   trader                                  0bps  29   21126236         21145773
```

Byte-for-byte the one-sided fixture. What has not happened is Brevis submitting the aggregated
proof on-chain, so `brevisCallback` never fired and `standing()` is still zero.

Watched for **47 minutes / 567 Sepolia blocks** against a documented ~2 minutes. Status never left
`QS_PAID`. The registry has exactly one event in its whole life: the `VkHashUpdated` from its own
deployment.

#### Is this our bug? Ruled out, one candidate at a time

The right instinct is that this stack is deterministic and should work, so each plausible
implementation fault was checked against the source rather than argued about:

| candidate | verdict |
|---|---|
| `submitProof` failing silently | **No.** `_submitProof` throws on `has_err` and the call is awaited inside our try/catch. It returned clean. |
| Wrong call order (pay before submitting the proof) | **No.** The SDK's own example is PrepareRequest -> SubmitProof -> sendRequest. That is our order. |
| Wrong `option` value | **No.** `QueryOption_ZK_MODE = 0` in gwproto; we pass 0. |
| `use_callback` not set | **No.** Both `buildAppCircuitInfo` (app.go) and `buildFullAppCircuitInfo` (prover/utils.go:57) hard-code `UseCallback: true`, and the prover's value is what we forward. |
| Wrong callback target, nonce, or fee | **No**, and this one is proven by Brevis, not by us. See the state machine below. |

#### The state machine locates the failure exactly

```
QS_TO_BE_PAID(1) -> QS_PAID(2) -> QS_PROOF_READY(3) -> QS_COMPLETE(4)
                         ^ we are here, and never moved
```

Reaching `QS_PAID` is the load-bearing fact. It means **Brevis matched our on-chain `sendRequest`
to our query**, so the proofId, nonce, callback target, callback gas and fee we submitted were all
correct, verified by the counterparty rather than asserted by us. The step that never ran is
`QS_PROOF_READY`, which is Brevis generating the final aggregated proof. That is their pipeline.

#### The service is dormant on both chains

Measured with `cast logs`, with a control to prove the query method works:

| contract | window | events |
|---|---|---|
| BrevisRequest, Sepolia | last 50,000 blocks (~7 days) | **1**, ours |
| BrevisRequest, Arbitrum One | last 5,000,000 blocks (~14 days) | **0** |
| BrevisProof, Arbitrum One | last 1,000,000 blocks | **0** |
| *control:* WETH, Arbitrum | last 2,000 blocks | 2,050 |
| *control:* v4 PoolManager, Arbitrum | last 20,000 blocks | 4,112 |

The controls matter: a failed range query and a genuinely empty result look identical, and the
controls show the query works and the endpoint is healthy. Arbitrum is the **one pair in Brevis'
current docs**, and its BrevisRequest has been untouched for a fortnight while the chain around it
is busy.

Brevis have publicly moved to ProverNet and the Pico stack. The appsdkv3 deployment these docs point
at appears retired, which is consistent with everything above: the gateway still accepts, prices and
correlates payments, but nothing aggregates.

**Conclusion: the round trip cannot complete through appsdkv3 on any chain, and no change to this
repo would alter that.** Every step we own is verified working.

This is **not** a fault in our contracts: the registry is configured, the callback target is
correct, the vk hash matches, and the output is ready and correct.

**A second correction: the Sepolia address we used is not the one on Brevis' legacy page.** That page
lists Sepolia as `0x841ce48F9446C8E281D3F1444cB859b4A6D0738C` (SDK v0.2). We used
`0xa082F86d9d1660C29cf3f962A31d7D20E367154F`, which comes from Brevis' own quickstart repository
(`brevis/contracts/deploy/TokenTransferZkOnly.ts:12`, commented "Sepolia Brevis Request Contract
Address"). So the earlier line "Sepolia is on Brevis' legacy page" was wrong: our deployment is on
neither the current page nor the legacy page. Both Sepolia deployments were surveyed and both are
receiving no traffic, so the distinction does not change the outcome, but the claim as written was
false.

**The limit of what this shows.** 47 minutes of silence does not prove fulfilment workers are off;
a badly backed-up queue looks identical from outside. The claim is bounded by what was measured:
*no callback within 47 minutes*. Do not upgrade it to *"Brevis has shut Sepolia down"*, which is a
claim about their infrastructure that we cannot see.

### Re-checked 2026-09-02 21:05 UTC, 11 h 24 m after payment

Nothing had moved. What the re-check added is not more waiting, it is four things that were not
established before.

**1. The gateway is holding a correct, decodable result.** `GetQueryStatus` returns `circuit_output`
populated, and it decodes through the deployed registry's own `decodeOutput`, not through a
hand-written parser:

```
$ cast call 0x03F05F1c89b9725F2AD775Aed85F60DD38af19B5     "decodeOutput(bytes)(address,uint16,uint16,uint64,uint64)"     0x308c6fbd6a14881af333649f17f2fde9cd75e2a60000001d0000000001425c5c000000000142a8ad     --rpc-url $RPC

0x308C6fbD6a14881Af333649f17f2FdE9cd75e2a6
0
29
21126236
21145773
```

0 bps over 29 swaps, block range 21,126,236 to 21,145,773, which is the one-sided fixture exactly and
sits under the pinned anchor at 21,146,236. Anyone can reproduce this from the raw gateway response
without trusting us. **This is the strongest available statement short of a callback**: the work is
finished and correct, and only delivery is outstanding.

**2. The fee we paid was right, and the contract says so.** `cast tx` shows `value 0`, and the
`RequestSent` event BrevisRequest emitted itself carries `fee` as its fourth field, also 0:

```
RequestSent(bytes32 proofId, uint64 nonce, address refundee, uint256 fee, (address,uint64) callback, uint8 option)
```

The amount is therefore confirmed by the counterparty contract rather than by our reading of a
gateway quote, and an underpayment would have reverted `sendRequest` rather than emitting.

**3. Resubmitting the proof changes nothing, and costs nothing.** `SubmitAppCircuitProof` is a
gateway RPC keyed on `(query_hash, nonce, target_chain_id)` with no value and no signer
(`sdk/gateway_client.go:65`, `sdk/app.go:709`), so it cannot incur a second payment. It was called
once and returned `success:true`; the status stayed `QS_PAID`. The gateway's full RPC surface
contains no retrigger or refulfil endpoint, so this was the last lever on our side.

**4. The provers are registered and active. No prover has transacted since before our payment.**

| check | Sepolia `0xa082F86d…` |
|---|---|
| `paused()` | false |
| `numProvers()` | 3 |
| `isActiveProver()` on each | true, true, true |
| nonce of each, oldest readable block vs head | unchanged |

**A retracted claim, recorded rather than quietly fixed.** The first version of this section said all
three provers made their last transaction on Sep 1 between 10:33 and 10:35 UTC, and read significance
into three independently keyed addresses stopping within two minutes of each other. **That was an
artifact of the measurement.** The last-transaction blocks were found by binary-searching each
prover's nonce, and the public RPC prunes state beyond a rolling window of roughly 10,000 blocks:

```
$ cast nonce 0x58b529F9084D7eAA598EB3477Fe36064C5B7bbC1 --block 11612213 --rpc-url $RPC
Error: server returned an error response: error code -32603: state at block #11612214 is pruned
$ cast nonce 0x58b529F9084D7eAA598EB3477Fe36064C5B7bbC1 --block 11612300 --rpc-url $RPC
482
```

The search converged on the **pruning boundary**, not on the last transaction, and because that
boundary moves with the chain, two runs an hour apart returned two different "last transaction"
blocks. The three addresses agreed with each other because they were all reporting the same edge.

What survives is weaker and still useful: each prover's nonce is identical at the oldest readable
block and at the head, so **no prover has sent a transaction in the last ~10,000 Sepolia blocks**,
a window that contains our payment and every hour since. What does not survive is any statement
about when they stopped, or that they stopped together.

**The archive-independent measurement.** `eth_getLogs` is served over wide ranges even by pruned
nodes, because logs are not state. Counting events on every BrevisRequest deployment Brevis
documents:

| chain | BrevisRequest | window | events |
|---|---|---|---|
| Arbitrum One 42161 | `0x91540fe3…` (current docs, the one supported pair) | 4,000,000 blocks | **0** |
| Sepolia 11155111 | `0xa082F86d…` (Brevis quickstart, the one we paid) | 150,000 blocks | **1**, ours |
| Sepolia 11155111 | `0x841ce48F…` (legacy page, SDK v0.2) | 150,000 blocks | **0** |
| Optimism 10 | `0x9f5b558c…` (legacy page, SDK v0.1) | 4,000,000 blocks | **0** |
| Base 8453 | `0x3463b379…` (legacy page, SDK v0.1) | 4,000,000 blocks | **0** |
| BSC Testnet 97 | `0xF7E9CB6b…` (legacy page, SDK v0.2) | 48,000 blocks | **0** |
| Arbitrum One 42161 | BrevisProof `0x0fEc0b24…` | 500,000 blocks | **0** |
| Sepolia 11155111 | BrevisProof `0x70cFEb37…` | 150,000 blocks | **0** |

Every deployment is unpaused with active provers registered, and every one of them is receiving no
traffic at all. This is not specific to the chain we chose.

**Say it exactly this way.** "Paid, accepted, output verified ready, never fulfilled on a chain
Brevis lists as legacy" is a stronger and more checkable claim than either "it works" or "the
gateway is broken". Every step above has a transaction hash or a gateway response behind it.

### Deploy dry run against live Sepolia state

`scripts/Deploy.s.sol` simulated (no broadcast) against Sepolia:

```
TenureRegistry: 0xe8a133308f421aba4C468A4eAA1b0bc88ADb674B
TenureHook:     0xe961271000367bE9DB99F5353E9006f246A80080
vkHash verified on-chain: 0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8
fee-neutrality confirmed in the mined address bits
Estimated total gas 3,210,494  ->  ~0.0072 ETH at 2.2 gwei
```

The mined hook address ends `0080`, `BEFORE_SWAP_FLAG` and nothing else, so the deployed hook is
structurally incapable of touching execution economics. Addresses above are simulation output and
will differ on a real broadcast, since the deployer address feeds CREATE2 mining.

### What is still NOT claimed

**No proof has landed on any chain.** The gateway accepts and prices the query; the paid
`sendRequest` leg and the `brevisCallback` it triggers have not been run. Until a
`StandingRecorded` event exists on a real chain, the claim is *"the gateway accepts our proofs"*, 
not *"the ZK path is live end to end"*.
