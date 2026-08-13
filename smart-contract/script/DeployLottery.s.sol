// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {FundSubscription, AddConsumer} from "./Interactions.s.sol";

error DeployLottery__MissingSubscriptionId();

/// @notice Deploys Lottery against an already-created VRF subscription; see NOTE.md before running.
contract DeployLottery is Script {
    function run() external returns (Lottery, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        uint256 subscriptionId = vm.envOr("SUBSCRIPTION_ID", config.subscriptionId);
        if (subscriptionId == 0) revert DeployLottery__MissingSubscriptionId();

        new FundSubscription().fundSubscription(config.vrfCoordinator, subscriptionId);

        vm.startBroadcast();
        Lottery lottery = new Lottery(
            config.vrfCoordinator,
            config.priceFeed,
            config.interval,
            config.keyHash,
            subscriptionId,
            config.callbackGasLimit,
            config.priceFeedStaleAfter
        );
        vm.stopBroadcast();

        new AddConsumer().addConsumer(config.vrfCoordinator, subscriptionId, address(lottery));

        return (lottery, helperConfig);
    }
}
