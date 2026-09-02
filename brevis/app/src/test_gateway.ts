// Probe: does the Brevis gateway accept a query for OUR production circuit?
//
// This is a diagnostic, not part of the submission path. It answers one question that decides
// whether deploying to Sepolia is worth anything: can a proof from DirectionalBalanceCircuit
// actually reach the gateway, or does PrepareQuery reject it?
//
// The earlier failure was an application-layer INTERNAL / RST_STREAM, not a connection failure,
// which has two readings we could not distinguish: a Brevis-side outage, or an unregistered app
// circuit. This run re-tests it and reports the exact error either way.
//
//   npm run gateway

import { Prover, Brevis, ProofRequest, ReceiptData, Field, asUint248 } from 'brevis-sdk-typescript';
import * as fs from 'fs';
import * as path from 'path';

const POOL = '0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640';
const SRC_CHAIN = 1;          // mainnet — where the swap logs live
const DST_CHAIN = 11155111;   // sepolia — where a callback would land

async function main() {
    const f = JSON.parse(
        fs.readFileSync(path.resolve(__dirname, '../fixtures/proof_inputs.json'), 'utf8'),
    ).onesided; // 29 receipts, the cheaper of the two

    const prover = new Prover('localhost:33247');
    const req = new ProofRequest();
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

    console.log('step 2/2  submitting to appsdkv3.brevis.network:443 ...');
    const brevis = new Brevis('appsdkv3.brevis.network:443');
    try {
        const out = await brevis.submit(req, res, SRC_CHAIN, DST_CHAIN, 0, '', '');
        console.log('');
        console.log('GATEWAY ACCEPTED THE QUERY');
        console.log('  queryKey:', JSON.stringify(out.queryKey));
        console.log('  fee     :', (out as any).fee ?? '(none quoted)');
        console.log('');
        console.log('=> the full path is available. Deploying to Sepolia is worth doing.');
    } catch (e: any) {
        console.log('');
        console.log('GATEWAY REJECTED THE QUERY');
        console.log('  code   :', e.code);
        console.log('  details:', e.details ?? e.message);
        console.log('');
        console.log('=> local proving works; the gateway leg does not. Disclosure stands.');
        process.exit(1);
    }
}

main().catch((e) => {
    console.error(e?.details ?? e?.message ?? e);
    process.exit(1);
});
