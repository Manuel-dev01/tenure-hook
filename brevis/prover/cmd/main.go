package main

import (
	"flag"
	"fmt"
	"os"

	"prover/circuits"

	"github.com/brevis-network/brevis-sdk/sdk/prover"
)

var port = flag.Uint("port", 33247, "the gRPC port to start the service at")
var restPort = flag.Uint("rest-port", 33257, "the REST gateway port")

func main() {
	flag.Parse()

	// TENURE: the production circuit. Upstream's example (circuits.AppCircuit, a USDC-transfer
	// proof) was used to close the T1a round-trip gate and is retained in circuits/circuit.go for
	// reference only. DirectionalBalanceCircuit takes PoolAddress and Trader as custom inputs,
	// supplied per-proof as JSON and reflected onto the struct by the prover
	// (brevis-sdk sdk/prover/assign.go).
	//
	// TENURE CHANGE (2026-09-02): brevis-sdk v0.3.12 -> v0.3.33. Not a preference. v0.3.12
	// hard-codes the gateway's per-chain dummy input commitments in common/const.go, and the
	// gateway has since rotated them, so every query built by that SDK is rejected:
	//
	//   invalid app circuit chain 1 dummy input commitment 0x127d5d80...
	//
	// 0x127d5d80... is literally the v0.3.12 constant. v0.3.17+ fetches the values from the
	// gateway at build time instead (sdk/app.go, GetCircuitDummyInput), and Brevis document
	// 0.3.17 as the minimum supported version: "It is not backward-compatible."
	// Measured, not inferred - see analysis/production-circuit-proof.md.
	//
	// The v0.3.33 API differs in two ways: the source-chain RPC moved out of ServiceConfig into
	// a per-chain SourceChainConfigs list, and Serve takes an explicit REST port.
	proverService, err := prover.NewService(
		&circuits.DirectionalBalanceCircuit{},
		prover.ServiceConfig{
			SetupDir: "$HOME/circuitOut",
			SrsDir:   "$HOME/kzgsrs",
		},
		prover.SourceChainConfigs{
			// Must be ARCHIVE-capable: the SDK fetches historical receipts and MPT keys for the
			// proving range. Non-archive endpoints answer "not found". publicnode refuses archive
			// requests without a token; drpc serves them.
			&prover.SourceChainConfig{ChainId: 1, RpcUrl: "https://eth.drpc.org"},
		},
	)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	if err := proverService.Serve("localhost", *port, *restPort); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
