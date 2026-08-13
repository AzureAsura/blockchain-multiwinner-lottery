// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Lottery} from "../../src/Lottery.sol";
import {LotteryHandler} from "./LotteryHandler.sol";

contract LotteryInvariantTest is Test {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant INITIAL_PRICE = 2000e8;
    uint256 private constant STALE_AFTER = 3 hours;
    uint256 private constant INTERVAL = 1 hours;
    bytes32 private constant KEY_HASH = keccak256("keyHash");
    uint32 private constant CALLBACK_GAS_LIMIT = 500_000;

    Lottery private lottery;
    LotteryHandler private handler;

    function setUp() public {
        MockV3Aggregator feed = new MockV3Aggregator(FEED_DECIMALS, INITIAL_PRICE);
        VRFCoordinatorV2_5Mock coordinator = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 4e15);
        uint256 subId = coordinator.createSubscription();

        lottery = new Lottery(
            address(coordinator), address(feed), INTERVAL, KEY_HASH, subId, CALLBACK_GAS_LIMIT, STALE_AFTER
        );

        coordinator.addConsumer(subId, address(lottery));
        coordinator.fundSubscriptionWithNative{value: 1000 ether}(subId);

        handler = new LotteryHandler(lottery, coordinator, feed, INITIAL_PRICE, INTERVAL);
        targetContract(address(handler));
    }

    /// @dev The contract must always hold enough ETH to cover the pool plus every unclaimed prize.
    function invariant_solvency() public view {
        assertGe(address(lottery).balance, lottery.getPoolBalanceETH() + handler.totalClaimable());
    }
}
