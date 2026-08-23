// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CollectionFactory} from "../src/CollectionFactory.sol";
import {Marketplace} from "../src/Marketplace.sol";

/// @notice Deploys CollectionFactory + Marketplace.
///
/// Usage (Base Sepolia):
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url base_sepolia \
///     --broadcast \
///     --verify
///
/// Required .env values: PRIVATE_KEY, PLATFORM_FEE_RECIPIENT, WETH_ADDRESS
/// (see .env.example — WETH_ADDRESS defaults to Base's predeploy at
/// 0x4200000000000000000000000000000000000006, the same address on mainnet and Sepolia).
contract Deploy is Script {
    function run() external returns (CollectionFactory factory, Marketplace marketplace) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address feeRecipient = vm.envAddress("PLATFORM_FEE_RECIPIENT");
        address weth = vm.envAddress("WETH_ADDRESS");

        vm.startBroadcast(deployerPk);

        factory = new CollectionFactory(feeRecipient);
        marketplace = new Marketplace(feeRecipient, weth);

        vm.stopBroadcast();

        console.log("CollectionFactory deployed at:", address(factory));
        console.log("  -> NFTCollection implementation:", factory.implementation());
        console.log("Marketplace deployed at:        ", address(marketplace));
        console.log("Fee recipient:                  ", feeRecipient);
        console.log("WETH:                           ", weth);
    }
}
