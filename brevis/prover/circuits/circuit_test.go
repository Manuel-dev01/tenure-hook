package circuits

import (
	"os"
	"testing"

	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/brevis-network/brevis-sdk/test"
	"github.com/ethereum/go-ethereum/common"
)

// TestCircuit exercises UPSTREAM's example circuit, not Tenure's. It is retained because the
// example circuit is what closed the T1a round-trip gate and its evidence should stay
// reproducible; Tenure's own circuit is covered by directional_balance_s5_test.go.
//
// It has never run as shipped: upstream leaves the RPC as the literal string "RPC_URL", so the
// constructor fails to dial. Under brevis-sdk v0.3.33 it no longer even reaches that point, because
// sdk.NewBrevisApp indexes an empty variadic slice (app.go:246). Rather than leave a test that
// panics on `go test ./...`, it now SKIPS unless a real endpoint is supplied:
//
//	TENURE_RPC=https://... go test ./circuits/ -run TestCircuit
//
// Skipping is deliberate and stated. It is not evidence of anything, and nothing in the README
// cites it.
func TestCircuit(t *testing.T) {
	rpc := os.Getenv("TENURE_RPC")
	if rpc == "" {
		t.Skip("set TENURE_RPC to run upstream's example-circuit test; it needs a live archive endpoint")
	}
	localDir := t.TempDir()
	// See directional_balance_s5_test.go for why this is not sdk.NewBrevisApp.
	app, err := sdk.NewBrevisAppWithConfig(&sdk.BrevisAppConfig{
		SrcChainId: 1,
		RpcUrl:     rpc,
		OutDir:     localDir,
	})
	check(err)

	txHash := common.HexToHash(
		"0x8a7fc50330533cd0adbf71e1cfb51b1b6bbe2170b4ce65c02678cf08c8b17737")

	app.AddReceipt(sdk.ReceiptData{
		TxHash: txHash,
		Fields: []sdk.LogFieldData{
			{
				IsTopic:    true,
				LogPos:     0,
				FieldIndex: 1,
			},
			{
				IsTopic:    false,
				LogPos:     0,
				FieldIndex: 0,
			},
		},
	})

	appCircuit := &AppCircuit{}
	appCircuitAssignment := &AppCircuit{}

	circuitInput, err := app.BuildCircuitInput(appCircuit)
	check(err)

	///////////////////////////////////////////////////////////////////////////////
	// Testing
	///////////////////////////////////////////////////////////////////////////////

	test.ProverSucceeded(t, appCircuit, appCircuitAssignment, circuitInput)
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}
