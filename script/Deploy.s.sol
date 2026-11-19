// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/InvoiceEscrow.sol";

/// @notice Deploy InvoiceEscrow to Aevum Testnet (chain 44005).
/// @dev Usage:
///   source <(python3 -c "import json; w=json.load(open('../test-wallet.json')); print('export PRIVATE_KEY='+w[0]['private_key'])")
///   forge script script/Deploy.s.sol --rpc-url https://rpc-test.qday.info --broadcast
contract Deploy is Script {
    address constant TUSD8 = 0x456569838f1d43009A91ebA4263147Afd7233483;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        InvoiceEscrow escrow = new InvoiceEscrow(TUSD8);
        vm.stopBroadcast();
        console.log("InvoiceEscrow deployed at:", address(escrow));
        console.log("token (tUSD8):", address(escrow.token()));
    }
}
