package circuits

import (
	"encoding/binary"
	"math/big"
	"os"
	"testing"

	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/ethereum/go-ethereum/common"
)

// S5 CHECK — "Does this assertion pass for the reason it claims?" (VERIFY.md §2)
//
// A proof that verifies is NOT evidence that the circuit computes directional balance correctly:
// it only shows prover and verifier agree about whatever the circuit does compute. So this test
// drives the circuit with REAL Uniswap V3 swap-log values and asserts the OUTPUT VALUE against a
// figure computed by hand from those same logs.
//
// Pool: USDC/WETH 0.05% — 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640
//
//	balanced  0x51c72848c68a965f66fa7a88855f9f7784502a7f
//	  11 buys / 7 sells, blocks 25831950..25832026   -> expect 7777 bps
//	one-sided 0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45
//	  4 buys / 0 sells, blocks 25832016..25832022   -> expect 0 bps
//
// Values were read from eth_getLogs independently of this circuit; expected balance is
// 2*min(buys,sells)*10000/total, computed outside it. If circuit and hand computation disagree,
// the circuit is wrong.
//
// WHY MOCK RECEIPTS. Supplying field values directly exercises the circuit's COMPUTATION without
// the MPT-proof path. Keeping the two separate is the point: this test should fail for arithmetic
// reasons only, never because an RPC or a block encoding moved.
//
// It also used to be a necessity. Under brevis-sdk v0.3.12 the proof path could not run against
// recent mainnet blocks at all - it failed with "transaction type not supported", because building
// the trie decodes every transaction in the block and current blocks carry EIP-7702 (type 4) that
// the SDK could not parse. v0.3.33 pins a go-ethereum fork that does parse type 4, so that is
// likely no longer true; it has not been retested, and this test does not depend on it either way.
// The proof path is covered separately by the T1a round trip and by the two production fixtures.

type mockSwap struct {
	block   int
	logPos  int
	amount0 string // 32-byte two's-complement, exactly as it appears in the log data
}

var balancedSwaps = []mockSwap{
	{block: 25831992, logPos: 2, amount0: "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffdad440060"},
	{block: 25831997, logPos: 2, amount0: "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffff8db73abb5"},
	{block: 25831998, logPos: 2, amount0: "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffff5907a5f44"},
	{block: 25831999, logPos: 2, amount0: "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffe8175dc0c"},
	{block: 25832000, logPos: 2, amount0: "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffface5a4421"},
	{block: 25832006, logPos: 2, amount0: "0x0000000000000000000000000000000000000000000000000000000b7856affa"},
	{block: 25832017, logPos: 2, amount0: "0x00000000000000000000000000000000000000000000000000000004570b2311"},
	{block: 25832024, logPos: 2, amount0: "0x000000000000000000000000000000000000000000000000000000013289ea40"},
	{block: 25832025, logPos: 2, amount0: "0x00000000000000000000000000000000000000000000000000000008307c71a5"},
	{block: 25832026, logPos: 2, amount0: "0x000000000000000000000000000000000000000000000000000000015a35509d"},
	{block: 25831950, logPos: 2, amount0: "0x00000000000000000000000000000000000000000000000000000005d09d48d5"},
	{block: 25831954, logPos: 2, amount0: "0x00000000000000000000000000000000000000000000000000000006c98835be"},
	{block: 25831957, logPos: 2, amount0: "0x000000000000000000000000000000000000000000000000000000074b2a0338"},
	{block: 25831960, logPos: 2, amount0: "0x0000000000000000000000000000000000000000000000000000000175f61a96"},
	{block: 25831961, logPos: 2, amount0: "0x00000000000000000000000000000000000000000000000000000001e574cf03"},
	{block: 25831963, logPos: 2, amount0: "0x000000000000000000000000000000000000000000000000000000051bfebdf0"},
	{block: 25831973, logPos: 2, amount0: "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffff7f05d68f9"},
	{block: 25831981, logPos: 2, amount0: "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffff9e84a8722"},
}

var oneSidedSwaps = []mockSwap{
	{block: 25832016, logPos: 2, amount0: "0x0000000000000000000000000000000000000000000000000000000000049147"},
	{block: 25832016, logPos: 2, amount0: "0x0000000000000000000000000000000000000000000000000000000000070044"},
	{block: 25832016, logPos: 2, amount0: "0x0000000000000000000000000000000000000000000000000000000000032e1d"},
	{block: 25832022, logPos: 2, amount0: "0x0000000000000000000000000000000000000000000000000000000001c9c380"},
}

const poolAddr = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"

const balancedTrader = "0x51c72848c68a965f66fa7a88855f9f7784502a7f"

func runBalance(t *testing.T, trader string, swaps []mockSwap) (addr common.Address, balanceBps, total, minBlock, maxBlock uint64) {
	t.Helper()
	// A live URL is required only because the constructor dials on construction; mock receipts
	// carry their own field values and no RPC lookup happens for them.
	rpc := os.Getenv("TENURE_RPC")
	if rpc == "" {
		rpc = "https://ethereum-rpc.publicnode.com"
	}
	// NOT sdk.NewBrevisApp. That convenience wrapper is broken in brevis-sdk v0.3.33: it forwards
	// gatewayUrlOverride[0] from a variadic parameter without checking the length, so calling it
	// with three arguments panics with "index out of range [0] with length 0" (app.go:246).
	// Passing a fourth argument avoids the panic but is worse - any explicit gateway URL makes
	// NewGatewayClient dial with INSECURE credentials (gateway_client.go), which cannot reach the
	// real TLS gateway. NewBrevisAppWithConfig with an empty GatewayUrl is the one path that both
	// avoids the panic and keeps TLS.
	app, err := sdk.NewBrevisAppWithConfig(&sdk.BrevisAppConfig{
		SrcChainId: 1,
		RpcUrl:     rpc,
		OutDir:     t.TempDir(),
	})
	if err != nil {
		t.Fatalf("NewBrevisAppWithConfig: %v", err)
	}
	pool := common.HexToAddress(poolAddr)
	traderAddr := common.HexToAddress(trader)
	for _, s := range swaps {
		app.AddMockReceipt(sdk.ReceiptData{
			BlockNum: big.NewInt(int64(s.block)),
			// Required by goPack even for mocks; not read by this circuit.
			BlockBaseFee: big.NewInt(0),
			MptKeyPath:   big.NewInt(0),
			Fields: []sdk.LogFieldData{
				// field 0 — recipient, topics[2] of the V3 Swap event
				{Contract: pool, IsTopic: true, LogPos: uint(s.logPos), FieldIndex: 2,
					Value: common.BytesToHash(traderAddr.Bytes())},
				// field 1 — amount0, first unindexed data word; its sign is the direction
				{Contract: pool, IsTopic: false, LogPos: uint(s.logPos), FieldIndex: 0,
					Value: common.HexToHash(s.amount0)},
			},
		})
	}
	circuit := &DirectionalBalanceCircuit{
		PoolAddress: sdk.ConstUint248(pool),
		Trader:      sdk.ConstUint248(traderAddr),
	}
	in, err := app.BuildCircuitInput(circuit)
	if err != nil {
		t.Fatalf("BuildCircuitInput: %v", err)
	}
	out := in.GetAbiPackedOutput()
	if len(out) < 40 {
		t.Fatalf("output too short: %d bytes (%x)", len(out), out)
	}
	copy(addr[:], out[0:20])
	balanceBps = uint64(binary.BigEndian.Uint16(out[20:22]))
	total = uint64(binary.BigEndian.Uint16(out[22:24]))
	minBlock = binary.BigEndian.Uint64(out[24:32])
	maxBlock = binary.BigEndian.Uint64(out[32:40])
	return
}

func TestS5_BalancedVersusOneSided(t *testing.T) {
	oAddr, oBps, oTotal, oMin, oMax := runBalance(t, "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45", oneSidedSwaps)
	t.Logf("one-sided %s -> balance=%d bps swaps=%d blocks %d..%d", oAddr, oBps, oTotal, oMin, oMax)
	if oBps != 0 {
		t.Errorf("one-sided balance = %d bps, want 0", oBps)
	}
	if oTotal != 4 {
		t.Errorf("one-sided total = %d, want 4", oTotal)
	}

	bAddr, bBps, bTotal, bMin, bMax := runBalance(t, "0x51c72848c68a965f66fa7a88855f9f7784502a7f", balancedSwaps)
	t.Logf("balanced  %s -> balance=%d bps swaps=%d blocks %d..%d", bAddr, bBps, bTotal, bMin, bMax)
	if bBps != 7777 {
		t.Errorf("balanced balance = %d bps, want 7777", bBps)
	}
	if bTotal != 18 {
		t.Errorf("balanced total = %d, want 18", bTotal)
	}

	// The direction of the difference is the whole point.
	if bBps <= oBps {
		t.Errorf("two-sided history must score HIGHER: balanced=%d one-sided=%d", bBps, oBps)
	}

	// The attested window must match the real block range, so the lookback is provable rather
	// than asserted by whoever assembled the receipts.
	if bMin != 25831950 || bMax != 25832026 {
		t.Errorf("attested window %d..%d, want 25831950..25832026", bMin, bMax)
	}
}

// TestS5_LookbackSensitivity captures directional balance for one address across three lookback
// windows. Parameter sensitivity is the strongest attack on this design — "change the lookback and
// the same address flips" — so the answer is to publish how much it actually moves rather than to
// argue. Numbers here are produced BY THE CIRCUIT, not computed alongside it.
//
// Windows are expressed as the most recent N blocks of the observed range, which is what a
// deployment would actually configure.
func TestS5_LookbackSensitivity(t *testing.T) {
	maxBlk := 0
	for _, s := range balancedSwaps {
		if s.block > maxBlk {
			maxBlk = s.block
		}
	}
	for _, span := range []int{20, 40, 80} {
		cutoff := maxBlk - span
		var window []mockSwap
		for _, s := range balancedSwaps {
			if s.block > cutoff {
				window = append(window, s)
			}
		}
		if len(window) == 0 {
			t.Logf("window %3d blocks: no swaps", span)
			continue
		}
		_, bps, total, lo, hi := runBalance(t, balancedTrader, window)
		t.Logf("window %3d blocks: balance=%5d bps  swaps=%2d  blocks %d..%d", span, bps, total, lo, hi)
	}
}
