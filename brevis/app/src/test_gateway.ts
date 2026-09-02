// Probe: does the Brevis gateway accept a query for OUR production circuit?
//
// This is a diagnostic, not part of the submission path.
//
// HISTORY, because this probe has now overturned two wrong explanations of the same rejection:
//
//   1. "Brevis-side outage."  False. The first failure was an application-layer RST_STREAM
//      against the UPSTREAM EXAMPLE circuit, which is a different, possibly transient fault.
//   2. "Our app circuit is not registered with Brevis."  Also false. There is no registration
//      step: Brevis document the partner key and callback address as NOT required, and both may
//      be empty strings (as they are below).
//
// The actual cause, traced rather than inferred: brevis-sdk v0.3.12 HARD-CODES the gateway's
// per-chain dummy input commitments in common/const.go. The gateway rotated them. So v0.3.12
// builds every query around a stale constant and the gateway rejects it by name:
//
//   invalid app circuit chain 1 dummy input commitment 0x127d5d80...
//
// 0x127d5d805cfd68acd5c88659d1cf96bcec545959ed27b8d654e90a8d9165501d is, verbatim,
// DummyReceiptInputCommitment[1] in v0.3.12. Querying the live gateway's GetCircuitDummyInput
// for chain 1 returns 0x182b42857c3565a60237a9d9f8e98a90a542019aa317623c4ade5f3c0d8f44ad
// instead. v0.3.17+ stopped hard-coding these and fetches them at build time; Brevis document
// 0.3.17 as the minimum: "It is not backward-compatible."
//
// Usage:
//   npm run gateway              # destination Arbitrum (42161), the current supported pair
//   npm run gateway -- 11155111  # destination Sepolia, a LEGACY appsdkv2 deployment

import { Prover, Brevis, ReceiptData, Field, asUint248 } from 'brevis-sdk-typescript';
import { ChainScopedProofRequest, SRC_CHAIN } from './chain_scoped_request';
import * as fs from 'fs';
import * as path from 'path';

const POOL = '0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640';
// Brevis' current deployment proves chain 1 data onto Arbitrum. Sepolia is on their legacy
// (appsdkv2) page, so it is available here only to demonstrate that it is not routed.
const DST_CHAIN = Number(process.argv[2] ?? 42161);

async function main() {
    const f = JSON.parse(
        fs.readFileSync(path.resolve(__dirname, '../fixtures/proof_inputs.json'), 'utf8'),
    ).onesided; // 29 receipts, the cheaper of the two

    const prover = new Prover('localhost:33247');
    const req = new ChainScopedProofRequest(SRC_CHAIN);
    f.rows.forEach((r: any, i: number) => {
        req.addReceipt(
            new ReceiptData({
                tx_hash: r.tx,
                fields: [
                    new Field({ log_pos: r.logPos, is_topic: true, field_index: 2 }),
                    new Field({ log_pos: r.logPos, is_topic: false, field_index: 0 }),
                ],
            }),
            i,
        );
    });
    req.setCustomInput({ PoolAddress: asUint248(POOL), Trader: asUint248(f.addr) });

    console.log('step 1/2  proving locally...');
    const res = await prover.prove(req);
    if (res.has_err) {
        console.error('LOCAL PROVING FAILED:', res.err.msg);
        process.exit(2);
    }
    console.log(`          proved, vk hash ${res.circuit_info.vk_hash}`);

    console.log(`step 2/2  submitting to appsdkv3.brevis.network:443, destination chain ${DST_CHAIN} ...`);
    const brevis = new Brevis('appsdkv3.brevis.network:443');
    try {
        // prepareQuery, not submit. Same gateway call submit() makes first, but it hands back the
        // whole PrepareQueryResponse instead of a two-field summary - which matters because the
        // FEE is the field that decides what msg.value sendRequest needs, and an earlier run
        // reported it as "0" without establishing whether that was a quote of zero or an unset
        // proto field rendering as zero. Those are different facts.
        const res1: any = await brevis.prepareQuery(req, res.circuit_info, SRC_CHAIN, DST_CHAIN, 0, '', '');
        if (res1.has_err) {
            console.log('');
            console.log('GATEWAY REJECTED THE QUERY');
            console.log('  ', res1.err.msg);
            process.exit(1);
        }

        const rawFee = res1.fee;
        const proofId = res1.query_key.query_hash;
        const nonce = res1.query_key.nonce;

        // Then submit the proof itself, so the query is actually queued and not just priced.
        await brevis.submitProof(res1.query_key, DST_CHAIN, res.proof);

        console.log('');
        console.log('GATEWAY ACCEPTED THE QUERY');
        console.log('  proofId :', proofId);
        console.log('  nonce   :', nonce);
        console.log(`  fee     : ${JSON.stringify(rawFee)}  (typeof ${typeof rawFee})`);
        console.log('');
        console.log('The fee is a base-10 STRING that the SDK parses into the msg.value for');
        console.log('BrevisRequest.sendRequest (brevis-sdk v0.3.33 sdk/app.go:642). An unset field');
        console.log('would be "" and would fail to parse; a genuine free quote is "0".');
        console.log('');
        console.log('Next, for scripts/PayRequest.s.sol:');
        console.log(`  PROOF_ID=${proofId}`);
        console.log(`  NONCE=${nonce}`);
        console.log(`  FEE_WEI=${rawFee === '' ? '0' : rawFee}`);
    } catch (e: any) {
        console.log('');
        console.log('GATEWAY REJECTED THE QUERY');
        console.log('  code   :', e.code);
        console.log('  details:', e.details ?? e.message);
        console.log('');
        console.log('=> local proving works; the gateway leg does not. Record the exact text above -');
        console.log('   do NOT summarise it as an outage or as a registration problem.');
        process.exit(1);
    }
}

main().catch((e) => {
    console.error(e?.details ?? e?.message ?? e);
    process.exit(1);
});
