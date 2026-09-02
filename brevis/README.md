# Brevis Quickstart Typescript

This repo contains a simple end-to-end brevis application
that proves circle USDC token transfer and handles the attested account and volume in an app contract.

## Environment Requirements

- Go >= 1.20
- Node.js LTS

## [Prover](./prover)

The prover service is a standalone process that is run on a server, preferably as a systemd managed process so that it can be auto restarted if any crash happens. The prover service is designed to be used in conjunction with [brevis-network/brevis-sdk-typescript](https://github.com/brevis-network/brevis-sdk-typescript). 

### Start Prover (for testing)

```bash
cd prover
make start
```

### Start Prover with Systemd (in production on linux server)

You may want to have a process daemon to manage the prover services in production. The [Makefile](prover/Makefileefile) in the project root contains some convenience scripts. 

To build, init systemd, and start both prover processes, run the following command. Note it requires sudo privilege because we want to use systemd commands

```bash
cd prover
make deploy
```

# [App](./app)

The Node.js project in ./app is a simple program that does the following things:

1. call the Go prover with some transaction data to generate token transfer volume proof
2. call Brevis backend service and submit the token transfer volume proof
3. wait until the final proof is submitted on-chain and our contract is called

## How to Run

```bash
cd app
npm run start [TransactionHash]
```
Example for Normal Flow
```bash
npm run start 0x8a7fc50330533cd0adbf71e1cfb51b1b6bbe2170b4ce65c02678cf08c8b17737
```

Example for Brevis Partner Flow
```bash
npm run start 0x8a7fc50330533cd0adbf71e1cfb51b1b6bbe2170b4ce65c02678cf08c8b17737 TestVolume 0x9fc16c4918a4d69d885f2ea792048f13782a522d
```
>[!NOTE]
>Brevis partner key **IS NOT** required to submit request to Brevis Gateway

# Contracts

Upstream's Hardhat project is **not part of this repository**. It deploys *their* example contract,
which Tenure does not use: our contracts are in `src/` and our deployments are Foundry scripts under
`scripts/`. See the [upstream repository](https://github.com/brevis-network/brevis-quickstart-ts)
for it, and [ATTRIBUTION.md](ATTRIBUTION.md) for what was vendored and from where.

Tenure's equivalent of the app contract is `src/TenureRegistry.sol`, which does the same three things
on callback: it checks the proof carries the expected verifying-key hash, decodes the circuit output,
and records the result.
