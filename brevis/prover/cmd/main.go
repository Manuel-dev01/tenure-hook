package main

import (
	"flag"
	"fmt"
	"os"

	"prover/circuits"

	"github.com/brevis-network/brevis-sdk/sdk/prover"
)

var port = flag.Uint("port", 33247, "the port to start the service at")

func main() {
	flag.Parse()

	// TENURE: the production circuit. Upstream's example (circuits.AppCircuit, a USDC-transfer
	// proof) was used to close the T1a round-trip gate and is retained in circuits/circuit.go for
	// reference only. DirectionalBalanceCircuit takes PoolAddress and Trader as custom inputs,
	// supplied per-proof as JSON and reflected onto the struct by the prover
	// (brevis-sdk sdk/prover/assign.go).
	proverService, err := prover.NewService(&circuits.DirectionalBalanceCircuit{}, prover.ServiceConfig{
		SetupDir: "$HOME/circuitOut",
		SrsDir:   "$HOME/kzgsrs",
		// TENURE CHANGE (2026-08-25): upstream default was https://eth.llamarpc.com,
		// whose origin returned Cloudflare 521 and aborted prover startup AFTER a
		// successful setup. Swapped for a public endpoint verified responding to
		// eth_blockNumber. Nothing else in this file is ours.
		// Must be ARCHIVE-capable: the pinned proving range is historical (pre-Pectra), and
		// non-archive endpoints answer "not found" when the SDK fetches receipts and MPT keys
		// for those blocks. publicnode refuses archive requests without a token.
		RpcURL:   "https://eth.drpc.org",
		ChainId:  1,
	})
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	proverService.Serve("", *port)
}
