// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/InvoiceEscrow.sol";

interface IERC20Full {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @notice Live end-to-end test against a deployed InvoiceEscrow on Aevum Testnet.
///  Flow: (1) payer approves + creates a 1 tUSD8 invoice for the payee,
///  (2) payee confirms receipt -> 1 tUSD8 released,
///  (3) payer creates a second 1 tUSD8 invoice with a short deadline,
///  (4) after the deadline, payer claims the refund.
///  Run with the PAYER key as PRIVATE_KEY and PAYEE address as env PAYEE.
///  The payee key (PAYEE_PRIVATE_KEY) is needed for step 2.
/// @dev Usage:
///   export PRIVATE_KEY=<payer key> PAYEE_PRIVATE_KEY=<payee key>
///   export PAYEE=<payee address> ESCROW=<deployed escrow address>
///   forge script script/E2E.s.sol --rpc-url https://rpc-test.qday.info --broadcast
contract E2E is Script {
    address constant TUSD8 = 0x456569838f1d43009A91ebA4263147Afd7233483;

    function run() external {
        address escrowAddr = vm.envAddress("ESCROW");
        address payee = vm.envAddress("PAYEE");
        uint256 payerKey = vm.envUint("PRIVATE_KEY");
        uint256 payeeKey = vm.envUint("PAYEE_PRIVATE_KEY");
        address payer = vm.addr(payerKey);
        InvoiceEscrow escrow = InvoiceEscrow(escrowAddr);
        IERC20Full token = IERC20Full(TUSD8);

        // --- invoice 1: happy path, 1 tUSD8 (1_000_000 units) ---
        vm.startBroadcast(payerKey);
        token.approve(escrowAddr, 2_000_000);
        uint256 id0 = escrow.createInvoice(payee, 1_000_000, block.timestamp + 7 days, "E2E invoice #1 - web design");
        vm.stopBroadcast();
        console.log("invoice #1 id:", id0);

        vm.startBroadcast(payeeKey);
        escrow.confirmReceipt(id0);
        vm.stopBroadcast();
        console.log("invoice #1 released; payee tUSD8:", token.balanceOf(payee));

        // --- invoice 2: refund path, 1 tUSD8, 60-second deadline ---
        vm.startBroadcast(payerKey);
        uint256 id1 = escrow.createInvoice(payee, 1_000_000, block.timestamp + 60, "E2E invoice #2 - refund test");
        vm.stopBroadcast();
        console.log("invoice #2 id:", id1, "(refund claimable after 60s)");
        console.log("escrow tUSD8 balance:", token.balanceOf(escrowAddr));
        console.log("NOTE: run ClaimRefund.s.sol after the deadline passes.");
    }
}

/// @notice Separate script for the refund leg (run >60s after E2E.s.sol).
///  forge script script/E2E.s.sol:ClaimRefund --rpc-url https://rpc-test.qday.info --broadcast
///  with PRIVATE_KEY=<payer key>, ESCROW=<address>, INVOICE_ID=<id>
contract ClaimRefund is Script {
    address constant TUSD8 = 0x456569838f1d43009A91ebA4263147Afd7233483;

    function run() external {
        address escrowAddr = vm.envAddress("ESCROW");
        uint256 invoiceId = vm.envUint("INVOICE_ID");
        uint256 payerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(payerKey);
        InvoiceEscrow(escrowAddr).claimRefund(invoiceId);
        vm.stopBroadcast();
        console.log("refund claimed for invoice:", invoiceId);
        console.log("payer tUSD8:", IERC20Full(TUSD8).balanceOf(vm.addr(payerKey)));
    }
}
