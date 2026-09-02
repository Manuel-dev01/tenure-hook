// Generate a directional-balance proof with the PRODUCTION circuit against real mainnet swap logs.
//
// This is the end-to-end local proving path for `DirectionalBalanceCircuit`:
//   real Uniswap V3 Swap receipts  ->  local prover (:33247)  ->  proof, verified against the vk
//
// The prover's prove() calls sdk.Verify internally and returns an error instead of a proof if
// verification fails, so receiving proof bytes IS verification.
//
// Receipts come from the PINNED PRE-PECTRA RANGE (see analysis/pinned-proving-range.md).
// That pinning was forced by brevis-sdk v0.3.12, which could not build receipt proofs against
// blocks containing EIP-7702 (type 4) transactions. v0.3.33 pins a go-ethereum fork that does
// parse type 4 (core/types/transaction.go: SetCodeTxType = 0x04), so the constraint is believed
// lifted - but these fixtures have NOT been re-cut against a post-Pectra range, so the pinning
// stands as a property of the fixtures, not of the SDK.
//
// Usage:  npm run prove -- <fixture>        fixture = "balanced" | "onesided"

import { Prover, ReceiptData, Field, asUint248, ErrCode } from 'brevis-sdk-typescript';
import { ChainScopedProofRequest, SRC_CHAIN } from './chain_scoped_request';
import * as fs from 'fs';
import * as path from 'path';

const POOL = '0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640'; // USDC/WETH 0.05%

interface Row {
    tx: string;
    logPos: number;
    a0: number;
    blk: number;
}
interface Fixture {
    addr: string;
    rows: Row[];
    buys: number;
    sells: number;
    expected_bps: number;
}

async function main() {
    const which = process.argv[2] ?? 'balanced';
    const fixturePath = path.resolve(__dirname, '../fixtures/proof_inputs.json');
    const fixtures: Record<string, Fixture> = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
    const f = fixtures[which];
    if (!f) {
        console.error(`unknown fixture '${which}'. available: ${Object.keys(fixtures).join(', ')}`);
        process.exit(1);
    }

    console.log(`fixture      : ${which}`);
    console.log(`trader       : ${f.addr}`);
    console.log(`receipts     : ${f.rows.length}  (buys ${f.buys} / sells ${f.sells})`);
    console.log(`EXPECTED     : ${f.expected_bps} bps  <- computed from raw logs, NOT by the circuit`);

    const prover = new Prover('localhost:33247');
    const proofReq = new ChainScopedProofRequest(SRC_CHAIN);

    f.rows.forEach((r, i) => {
        // The index is REQUIRED and must be distinct. The prover always pins by index
        // (sdk/prover/server.go:241), so omitting it makes every receipt land at 0 and the
        // second one panics with "an element already pinned at index 0".
        proofReq.addReceipt(
            new ReceiptData({
                tx_hash: r.tx,
                fields: [
                    // field 0, recipient, topics[2] of the V3 Swap event
                    new Field({ log_pos: r.logPos, is_topic: true, field_index: 2 }),
                    // field 1, amount0, first unindexed data word; its sign is the direction
                    new Field({ log_pos: r.logPos, is_topic: false, field_index: 0 }),
                ],
            }),
            i,
        );
    });

    // PoolAddress and Trader are circuit fields, supplied per-proof and reflected onto the struct
    // by the prover (brevis-sdk sdk/prover/assign.go).
    // setCustomInput takes a plain object and JSON-stringifies it itself; values are built with
    // asUint248 so they arrive as {type, data} pairs the Go side can decode. Field names must match
    // the struct fields on DirectionalBalanceCircuit.
    proofReq.setCustomInput({
        PoolAddress: asUint248(POOL),
        Trader: asUint248(f.addr),
    });

    console.log('\nproving...');
    const t0 = Date.now();
    const res = await prover.prove(proofReq);
    const secs = ((Date.now() - t0) / 1000).toFixed(1);

    if (res.has_err) {
        const err = res.err;
        switch (err.code) {
            case ErrCode.ERROR_INVALID_INPUT:
                console.error('invalid receipt input:', err.msg);
                break;
            case ErrCode.ERROR_INVALID_CUSTOM_INPUT:
                console.error('invalid custom input:', err.msg);
                break;
            case ErrCode.ERROR_FAILED_TO_PROVE:
                console.error('failed to prove:', err.msg);
                break;
            default:
                console.error('error:', err.msg);
        }
        process.exit(1);
    }

    console.log(`PROVED and verified in ${secs}s`);
    console.log(`proof bytes  : ${res.proof.length / 2 - 1}`);

    // Output layout, set by DirectionalBalanceCircuit:
    //   address(20) | balanceBps(2) | totalSwaps(2) | minBlock(8) | maxBlock(8)
    const info = res.circuit_info;
    console.log(`vk hash      : ${info.vk_hash}`);

    const hexRaw = info.output ?? '';
    const hex = hexRaw.startsWith('0x') ? hexRaw.slice(2) : hexRaw;
    if (hex.length < 80) {
        console.error(`unexpected output length ${hex.length}: ${hexRaw}`);
        process.exit(1);
    }
    const addr = '0x' + hex.slice(0, 40);
    const balanceBps = parseInt(hex.slice(40, 44), 16);
    const total = parseInt(hex.slice(44, 48), 16);
    const minBlock = parseInt(hex.slice(48, 64), 16);
    const maxBlock = parseInt(hex.slice(64, 80), 16);

    console.log('');
    console.log('--- circuit output ---');
    console.log(`  address    : ${addr}`);
    console.log(`  balance    : ${balanceBps} bps   (expected ${f.expected_bps})`);
    console.log(`  swaps      : ${total}   (expected ${f.rows.length})`);
    console.log(`  window     : ${minBlock}..${maxBlock}`);

    // A verifying proof is NOT evidence the circuit computed the right thing. Compare against the
    // figure derived from raw logs, independently of this circuit.
    let bad = false;
    if (addr.toLowerCase() !== f.addr.toLowerCase()) { console.error('MISMATCH: address'); bad = true; }
    if (balanceBps !== f.expected_bps) { console.error('MISMATCH: balance'); bad = true; }
    if (total !== f.rows.length) { console.error('MISMATCH: swap count'); bad = true; }
    if (bad) process.exit(1);

    console.log('');
    console.log('OK, proof verified AND output matches the figure computed from raw logs.');
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
