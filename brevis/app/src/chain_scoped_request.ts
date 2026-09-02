// A ProofRequest that names its source chain.
//
// WHY THIS EXISTS. brevis-sdk-typescript is pinned at 1.3.1 (published Nov 2024) because that is
// the newest version on npm - it has not tracked the Go SDK. Its `ProofRequest.build()` composes a
// `ProveRequest` from receipts, storages, transactions and custom input, and never sets
// `src_chain_id`, even though the field has existed in the proto the whole time.
//
// Under brevis-sdk v0.3.12 that was harmless: the prover was configured with exactly one chain and
// used it unconditionally. v0.3.33 replaced that single setting with a keyed `SourceChainConfigs`
// list, so an unset `src_chain_id` arrives as 0 and the prover rejects the request:
//
//     error: failed to create BrevisApp: unsupported chain ID: 0
//
// `Prover.prove()` calls `request.build()` itself, so there is no opportunity to amend the built
// message from outside. Overriding `build()` is the seam the SDK actually leaves open, and it
// keeps the fix inside our own source rather than patched into node_modules where a reinstall
// would silently drop it.

import { ProofRequest } from 'brevis-sdk-typescript';

// `ProveRequest` is not re-exported by the package, so name it structurally.
type ProveRequest = ReturnType<ProofRequest['build']>;

export class ChainScopedProofRequest extends ProofRequest {
    constructor(private readonly srcChainId: number) {
        super();
    }

    build(): ProveRequest {
        const req = super.build();
        req.src_chain_id = this.srcChainId;
        return req;
    }
}

/// Ethereum mainnet - where the swap logs being proven live.
export const SRC_CHAIN = 1;
