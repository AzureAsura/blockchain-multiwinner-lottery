// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @notice Creates a new VRF subscription; see NOTE.md before trusting its printed subId.
contract CreateSubscription is Script {
    function run() external returns (uint256 subId, address vrfCoordinator) {
        HelperConfig helperConfig = new HelperConfig();
        vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        subId = createSubscription(vrfCoordinator);
    }

    function createSubscription(address vrfCoordinator) public returns (uint256 subId) {
        vm.startBroadcast();
        subId = IVRFCoordinatorV2Plus(vrfCoordinator).createSubscription();
        vm.stopBroadcast();
    }
}

/// @notice Funds a VRF subscription with native ETH (matches the Lottery's nativePayment: true request).
contract FundSubscription is Script {
    uint256 public constant FUND_AMOUNT = 0.05 ether;

    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        uint256 subId = vm.envOr("SUBSCRIPTION_ID", config.subscriptionId);
        fundSubscription(config.vrfCoordinator, subId);
    }

    function fundSubscription(address vrfCoordinator, uint256 subId) public {
        vm.startBroadcast();
        IVRFCoordinatorV2Plus(vrfCoordinator).fundSubscriptionWithNative{value: FUND_AMOUNT}(subId);
        vm.stopBroadcast();
    }
}

/// @notice Registers a Lottery deployment as an allowed consumer on a VRF subscription.
contract AddConsumer is Script {
    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        uint256 subId = vm.envOr("SUBSCRIPTION_ID", config.subscriptionId);
        address lottery = vm.envAddress("LOTTERY_ADDRESS");
        addConsumer(config.vrfCoordinator, subId, lottery);
    }

    function addConsumer(address vrfCoordinator, uint256 subId, address consumer) public {
        vm.startBroadcast();
        IVRFCoordinatorV2Plus(vrfCoordinator).addConsumer(subId, consumer);
        vm.stopBroadcast();
    }
}
