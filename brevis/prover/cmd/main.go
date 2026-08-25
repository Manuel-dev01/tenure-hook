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

	proverService, err := prover.NewService(&circuits.AppCircuit{}, prover.ServiceConfig{
		SetupDir: "$HOME/circuitOut",
		SrsDir:   "$HOME/kzgsrs",
		// TENURE CHANGE (2026-08-25): upstream default was https://eth.llamarpc.com,
		// whose origin returned Cloudflare 521 and aborted prover startup AFTER a
		// successful setup. Swapped for a public endpoint verified responding to
		// eth_blockNumber. Nothing else in this file is ours.
		RpcURL:   "https://ethereum-rpc.publicnode.com",
		ChainId:  1,
	})
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	proverService.Serve("", *port)
}
