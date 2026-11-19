# InvoiceEscrow — Demo Frontend

Static single-page demo for the InvoiceEscrow contract (Aevum Builder Challenge #1).
No build step — just `index.html` + `abi.json`, with ethers.js v6 loaded from a CDN.

## What it does

- Connects MetaMask / any EIP-1193 wallet and switches (or adds) Aevum Testnet
  (chain ID 44005, RPC `https://rpc-test.qday.info`).
- Shows the connected address, tQDAY balance and tUSD8 balance.
- Create Invoice: enter payee, amount (tUSD8), deadline (days from now) and a
  description, then **Approve tUSD8** (exact amount) followed by
  **Create & Lock Invoice**.
- Lists every invoice on-chain (`invoiceCount` + `getInvoice`): id, payer, payee,
  amount, deadline, status (Funded / Released / Refunded), description.
  - **Confirm Receipt** appears only for the payee while the invoice is Funded.
  - **Claim Refund** appears only for the payer while the invoice is Funded and
    the deadline has passed.
- Every submitted transaction shows its hash with a link to the Aevum explorer
  (`https://explorer-test.qday.info/tx/<hash>`).

Everything reads/writes the real contract — no mock data.

## Contract address

The default contract address in `index.html` is the **live deployed**
address `0xaEd0EBf4B742eC853a8E50b87d1905a2680e9935` (deployed 2026-11-19,
deploy tx `0xb8dbf383…a958b7`, block 3554323 — it matched the predicted
deterministic address exactly). To point at a different deployment:

- paste the real address into the "Contract" field on the page and press
  "Use this contract", or
- open the page with `?contract=0x…`.

## Run locally

```bash
cd demo
python3 -m http.server 8080
# open http://localhost:8080
```

## Run with Docker

```bash
cd demo
docker build -t invoice-escrow-demo .
docker run --rm -p 8080:80 invoice-escrow-demo
# open http://localhost:8080
```

## Notes

- tUSD8 token: `0x456569838f1d43009A91ebA4263147Afd7233483` (6 decimals).
- You need testnet tQDAY for gas and tUSD8 to lock in an invoice — both come
  from the Aevum testnet faucet (`faucet.qday.info`).
- `abi.json` is the contract ABI extracted verbatim from the compiled output
  (`project/out/InvoiceEscrow.sol/InvoiceEscrow.json`).
