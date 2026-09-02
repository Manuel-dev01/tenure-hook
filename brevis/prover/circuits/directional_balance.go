package circuits

import (
	"math/big"

	"github.com/brevis-network/brevis-sdk/sdk"
)

// DirectionalBalanceCircuit proves how two-sided an address's swap history is on one pool.
//
// THE CLAIM, STATED NARROWLY:
//
//	"Of this address's swaps on this pool within the block range proven below, this fraction were
//	 balanced between the two directions."
//
// We do NOT claim to detect toxicity, adverse selection, or intent. Adverse-selection scoring was
// considered and rejected. It infers intent from subsequent price movement, which is the same
// mistake that killed the predecessor project (inferring an operation from a state prefix), and it
// needs a threshold on a continuous modelled score, which this project does not permit.
//
// CONSEQUENCE: this circuit reads swap logs and nothing else. No price series, no post-trade
// window, no oracle. If a price ever appears here, the claim has drifted back to adverse-selection
// scoring and the build must stop. scripts/gate.sh enforces that from stage 2 onward.
//
// THE WINDOW IS PART OF THE PROOF. The circuit outputs the lowest and highest block it actually
// saw, so the lookback window is attested rather than asserted off-chain. A verifier can tell which
// window a standing figure came from without trusting the submitter.
type DirectionalBalanceCircuit struct {
	// PoolAddress is the pool contract whose Swap logs count. Every receipt must come from it.
	PoolAddress sdk.Uint248

	// Trader is the address whose swaps are being measured, as it appears in the Swap log.
	Trader sdk.Uint248
}

var _ sdk.AppCircuit = &DirectionalBalanceCircuit{}

// BPS is the basis-point denominator. A perfectly two-sided history scores BPS.
const BPS = 10000

// MaxSwaps bounds how many Swap receipts one proof may consider.
const MaxSwaps = 32

// Allocate declares the data budget. Receipts only: this circuit reads swap logs and nothing else.
func (c *DirectionalBalanceCircuit) Allocate() (maxReceipts, maxStorage, maxTransactions int) {
	return MaxSwaps, 0, 0
}

// Define computes directional balance over the supplied Swap receipts.
//
// Each receipt supplies two fields from one Uniswap Swap log:
//
//	Field 0, the address the swap is attributed to, read from an indexed topic.
//	Field 1, amount0, signed. Its sign is the swap's direction.
//
// Both fields are asserted to come from the same log position, so the direction cannot be taken
// from one swap and the address from another.
func (c *DirectionalBalanceCircuit) Define(api *sdk.CircuitAPI, in sdk.DataInput) error {
	receipts := sdk.NewDataStream(api, in.Receipts)

	// --- provenance: every receipt must be a Swap log from the named pool, for the named trader ---
	//
	// Without these assertions the proof would say "somebody swapped somewhere", which is not a
	// statement about this address on this pool. This is the S1 guard: the circuit must not take
	// the association on faith from whoever assembled the input.
	sdk.AssertEach(receipts, func(r sdk.Receipt) sdk.Uint248 {
		fromPool := api.Uint248.IsEqual(r.Fields[0].Contract, c.PoolAddress)
		sameLog := api.ToUint248(api.Uint32.IsEqual(r.Fields[0].LogPos, r.Fields[1].LogPos))

		// Field 0 is an indexed address topic; field 1 is unindexed amount data.
		addrIsTopic := api.Uint248.IsEqual(r.Fields[0].IsTopic, sdk.ConstUint248(1))
		amtIsData := api.Uint248.IsEqual(r.Fields[1].IsTopic, sdk.ConstUint248(0))

		// The address in the log must be the trader we are measuring.
		isTrader := api.Uint248.IsEqual(api.ToUint248(r.Fields[0].Value), c.Trader)

		ok := api.Uint248.And(fromPool, sameLog)
		ok = api.Uint248.And(ok, addrIsTopic)
		ok = api.Uint248.And(ok, amtIsData)
		ok = api.Uint248.And(ok, isTrader)
		return ok
	})

	// --- direction ---
	//
	// amount0 is the pool's signed delta in token0. Negative and positive partition the two
	// directions exactly; a swap cannot be both, and amount0 == 0 is not a real swap.
	//
	// ToInt248 on a Bytes32 asserts the value is a properly sign-extended int, so a malformed
	// field cannot be smuggled through as a huge positive number.
	zero := sdk.ConstInt248(big.NewInt(0))

	sellSide := sdk.Filter(receipts, func(r sdk.Receipt) sdk.Uint248 {
		amount0 := api.ToInt248(r.Fields[1].Value)
		return api.Int248.IsLessThan(amount0, zero)
	})
	buySide := sdk.Filter(receipts, func(r sdk.Receipt) sdk.Uint248 {
		amount0 := api.ToInt248(r.Fields[1].Value)
		return api.Uint248.Not(api.Int248.IsLessThan(amount0, zero))
	})

	sells := sdk.Count(sellSide)
	buys := sdk.Count(buySide)
	total := api.Uint248.Add(sells, buys)

	// --- balance ---
	//
	// balance = 2 * min(buys, sells) / total, in basis points.
	//   perfectly two-sided  -> BPS
	//   entirely one-sided   -> 0
	//
	// This is a ratio of counts, deliberately not of volume: Brevis treats volume metrics as
	// ineligible, and counts are also harder to distort with a single large trade.
	//
	// Continuous and monotonic. There is no threshold here and none may be added, the
	// balance-to-depth mapping lives in the hook (src/TenureHook.sol:172), not in this circuit.
	buysLessThanSells := api.Uint248.IsLessThan(buys, sells)
	minSide := api.Uint248.Select(buysLessThanSells, buys, sells)

	// Guard the empty case: an address with no swaps has no balance to report, and dividing by
	// zero would otherwise be constrained to garbage rather than failing loudly.
	isEmpty := api.Uint248.IsZero(total)
	safeTotal := api.Uint248.Select(isEmpty, sdk.ConstUint248(1), total)

	numerator := api.Uint248.Mul(minSide, sdk.ConstUint248(2*BPS))
	balanceBps, _ := api.Uint248.Div(numerator, safeTotal)
	balanceBps = api.Uint248.Select(isEmpty, sdk.ConstUint248(0), balanceBps)

	// --- the attested window ---
	//
	// Emitting the observed block range makes the lookback window verifiable on-chain rather than
	// a claim from whoever assembled the receipts.
	minBlock := sdk.Reduce(receipts, sdk.ConstUint248(0),
		func(acc sdk.Uint248, r sdk.Receipt) sdk.Uint248 {
			blk := api.ToUint248(r.BlockNum)
			first := api.Uint248.IsZero(acc)
			lower := api.Uint248.IsLessThan(blk, acc)
			take := api.Uint248.Or(first, lower)
			return api.Uint248.Select(take, blk, acc)
		})
	maxBlock := sdk.Reduce(receipts, sdk.ConstUint248(0),
		func(acc sdk.Uint248, r sdk.Receipt) sdk.Uint248 {
			blk := api.ToUint248(r.BlockNum)
			higher := api.Uint248.IsGreaterThan(blk, acc)
			return api.Uint248.Select(higher, blk, acc)
		})

	// Output layout consumed by TenureRegistry in stage 3.
	api.OutputAddress(c.Trader)
	api.OutputUint(16, balanceBps)
	api.OutputUint(16, total)
	api.OutputUint(64, minBlock)
	api.OutputUint(64, maxBlock)

	return nil
}
