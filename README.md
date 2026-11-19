# Invoice Escrow — tUSD8 on Aevum Testnet

One working stablecoin payment flow for **Aevum Builder Challenge #1**
(track: **Invoice Payments**). A payer locks tUSD8 in escrow against an
invoice; the payee confirms receipt of the goods/services and the funds
release. If the deadline passes with no confirmation, the payer claims a
refund. No admin, no fees, no upgradeability.

- **Network:** QDay Aevum Testnet — chain ID **44005**, RPC
  `https://rpc-test.qday.info`, explorer `https://explorer-test.qday.info/`
- **Stablecoin:** tUSD8 `0x456569838f1d43009A91ebA4263147Afd7233483` (ERC-20, 6 decimals)
- **Contract:** `src/InvoiceEscrow.sol`
- **Deployed escrow:** `0xaEd0EBf4B742eC853a8E50b87d1905a2680e9935` — **LIVE on Aevum
  Testnet since 2026-11-19 ~13:55 WIB** (deploy tx
  `0xb8dbf3838fe6ca05e0e3c4dd2c83c243aef25c9d20f775f91da7163534a958b7`,
  block 3554323; matches the predicted deterministic address exactly).
  Explorer: https://explorer-test.qday.info/address/0xaEd0EBf4B742eC853a8E50b87d1905a2680e9935

## How it works

| Step | Who | What happens |
|---|---|---|
| 1. Create + lock | Payer | `createInvoice(payee, amount, deadline, description)` pulls tUSD8 via `transferFrom` (approve first). Invoice status: `Funded`. |
| 2. Confirm + release | Payee | `confirmReceipt(id)` sends the locked tUSD8 to the payee. Status: `Released`. |
| 3. Refund | Payer | After the deadline, `claimRefund(id)` returns the locked tUSD8 to the payer. Status: `Refunded`. |

Rules that make it escrow, not a plain transfer:

- The payer **cannot** pull funds back before the deadline (no cancel).
  The payee can ship knowing the money is locked.
- The payee **cannot** release funds to themselves early — release only
  happens through `confirmReceipt`, which pays the recorded payee.
- Every status transition is one-way (`Funded → Released | Refunded`);
  double-confirm and double-refund revert.
- Creation guards: zero amount, zero payee, payee == payer, and
  past-deadline all revert.

## Repo layout

```
src/InvoiceEscrow.sol   — the escrow contract (no dependencies beyond an IERC20 interface)
test/InvoiceEscrow.t.sol — 17 Foundry tests (happy path, refund, guards, access control)
script/Deploy.s.sol     — deploy to Aevum Testnet
script/E2E.s.sol        — live end-to-end test (release leg + refund leg, separate scripts)
demo/                   — static demo frontend (ethers.js) + Dockerfile
```

## Run the tests

```sh
export PATH="$HOME/.foundry/bin:$PATH"
forge test
# 17 tests, all passing (verified 2026-11-19)
```

## Deploy to Aevum Testnet (needs funded deploy wallet — see blocker below)

```sh
export PATH="$HOME/.foundry/bin:$PATH"
# PRIVATE_KEY = the throwaway deploy wallet (never a real wallet)
export PRIVATE_KEY=<deploy-wallet-key>
forge script script/Deploy.s.sol --rpc-url https://rpc-test.qday.info --broadcast
```

Then run the live end-to-end test (needs the payee wallet key too):

```sh
export ESCROW=<deployed address>
export PAYEE=<payee address> PAYEE_PRIVATE_KEY=<payee key>
forge script script/E2E.s.sol:E2E --rpc-url https://rpc-test.qday.info --broadcast
# wait >60s (invoice #2 has a 60s deadline), then:
export INVOICE_ID=1
forge script script/E2E.s.sol:ClaimRefund --rpc-url https://rpc-test.qday.info --broadcast
```

## Demo frontend

```sh
cd demo && python3 -m http.server 8000
# or: docker build -t invoice-escrow-demo . && docker run -p 8080:80 invoice-escrow-demo
```

Open the page, connect a wallet on chain 44005, and use the forms.
The demo defaults to the expected escrow address above and lets you
override it with `?contract=0x...`.

## Verification status (2026-11-19)

- **Unit tests:** 17/17 pass (`forge test`).
- **Fork E2E (local Anvil fork of Aevum Testnet, real tUSD8 contract):**
  deploy + invoice #1 create → confirm → release (payee received exactly
  1 tUSD8) + invoice #2 create → deadline → refund (payer refunded exactly
  1 tUSD8). Final balances: payer 9 tUSD8, payee 1 tUSD8, escrow 0.
  Invoice states read back on-chain: #0 `Released`, #1 `Refunded`.
- **Live testnet deploy + live E2E: DONE 2026-11-19 ~13:55–14:02 WIB**
  (funded via Discord `/faucet` — 1 tQDAY + 5 tUSD8 to the throwaway).
  Deploy tx `0xb8dbf383…a958b7` (block 3554323). Invoice #0 create →
  confirm → release: payee received exactly 1 tUSD8 (tx
  `0x3e59a935…8930a0bd`, block 3557017). Invoice #1 create → 60 s deadline
  → refund: payer refunded exactly 1 tUSD8 (tx
  `0x9de82fab…4284b5`, block 3557030). Final balances: payer 4 tUSD8, payee
  1 tUSD8, escrow 0. Invoice states verified via events (#0 `Released`,
  #1 `Refunded`) — see the chain quirk below.
- **Chain quirk (found live, 2026-11-19):** the Aevum Testnet node rejects
  the `MCOPY` opcode, so the `getInvoice()` / `invoices()` views (which
  return the struct's string field) revert on-chain, even though the
  state-changing flows work fine. The demo lists invoices from events
  when the direct read fails (`demo/index.html`, `invoiceFromEvents`).
  A fix-at-the-contract level (fixed-size-only getter) would need a
  redeploy; the event fallback keeps the deployed contract as-is.

## ~~Blocker: testnet funds~~ — RESOLVED 2026-11-19 (Discord `/faucet`)

The throwaway deploy wallet `0x4e8eAC332087896079b2019E2926Db1b8e2aD2CE`
holds **0 tQDAY and 0 tUSD8**, and the official faucet will not fund it:

- The faucet (`faucet.qday.info`) requires the **recipient** to hold
  ≥ 0.0001 ETH **or** ≥ 1 USDT/USDC **on Ethereum mainnet**
  (verified live: `GET /gasapi/eligibility?address=<throwaway>` →
  `{"eligible":false,"via":null}`; eligibility rules in `/gasapi/info`:
  `ethMinWei: 100000000000000`, `stableMinUnits: 1000000`).
- The user's two known addresses were checked on mainnet and both hold
  **0 ETH and 0 USDT**, so they cannot be the faucet recipient either.
- The tUSD8 claim additionally requires a Cloudflare Turnstile bot check
  (browser/human step) — it cannot be scripted.

**What the user must do (pick one):**

- **Option A (simplest):** join the QDay Discord, get verified, and run
  `/faucet 0x4e8eAC332087896079b2019E2926Db1b8e2aD2CE` in the #faucet
  channel → 1 tQDAY + 5 tUSD8 straight to the throwaway deploy wallet.
  That is enough for the deploy (~0.002 tQDAY at 1 gwei) and the live E2E
  (2 tUSD8).
- **Option B:** claim on `faucet.qday.info` from a wallet that **does**
  hold ≥ 0.0001 ETH or ≥ 1 USDT/USDC on Ethereum mainnet, then send the
  test tokens (≥ 0.01 tQDAY + ≥ 2 tUSD8) to the throwaway address above.

Once the throwaway holds test tokens, the deploy + live E2E are two
commands (see above) and the demo's contract address gets confirmed.

## License

MIT. Third-party dependencies: Foundry `forge-std` (MIT), ethers.js (MIT).
