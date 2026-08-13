// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Lottery} from "../src/Lottery.sol";

contract LotteryIntegrationTest is Test {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant INITIAL_PRICE = 2000e8;
    uint256 private constant STALE_AFTER = 3 hours;
    uint256 private constant INTERVAL = 7 days;
    bytes32 private constant KEY_HASH = keccak256("keyHash");
    uint32 private constant CALLBACK_GAS_LIMIT = 500_000;

    MockV3Aggregator private feed;
    VRFCoordinatorV2_5Mock private coordinator;
    Lottery private lottery;
    uint256 private nextRequestId = 1;

    function setUp() public {
        feed = new MockV3Aggregator(FEED_DECIMALS, INITIAL_PRICE);
        coordinator = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 4e15);
        uint256 subId = coordinator.createSubscription();

        lottery = new Lottery(
            address(coordinator), address(feed), INTERVAL, KEY_HASH, subId, CALLBACK_GAS_LIMIT, STALE_AFTER
        );

        coordinator.addConsumer(subId, address(lottery));
        coordinator.fundSubscriptionWithNative{value: 10 ether}(subId);
    }

    /// @dev Buys a ticket for `buyer` and returns the price actually paid.
    function _buy(address buyer, Lottery.Tier tier) private returns (uint256 price) {
        price = lottery.getTicketPriceInWei(tier);
        vm.deal(buyer, price);
        vm.prank(buyer);
        lottery.buyTicket{value: price}(tier);
    }

    /// @dev Advances past the interval, triggers the draw, and fulfills it with chosen random words.
    function _runDraw(uint256[] memory randomWords) private {
        vm.warp(block.timestamp + INTERVAL);
        feed.updateAnswer(INITIAL_PRICE);
        lottery.performUpkeep("");
        coordinator.fulfillRandomWordsWithOverride(nextRequestId, address(lottery), randomWords);
        nextRequestId++;
    }

    function test_fullRound_allThreeTiersActive_paysWinnersAndLeavesNoDust() public {
        address buyerOne = makeAddr("buyerOne");
        address buyerFive = makeAddr("buyerFive");
        address buyerTenA = makeAddr("buyerTenA");
        address buyerTenB = makeAddr("buyerTenB");

        uint256 priceOne = _buy(buyerOne, Lottery.Tier.ONE);
        uint256 priceFive = _buy(buyerFive, Lottery.Tier.FIVE);
        uint256 priceTen = _buy(buyerTenA, Lottery.Tier.TEN);
        _buy(buyerTenB, Lottery.Tier.TEN);

        uint256 pool = priceOne + priceFive + (priceTen * 2);
        assertEq(lottery.getPoolBalanceETH(), pool);

        uint256[] memory randomWords = new uint256[](3);
        randomWords[2] = 1; // 1 % 2 == 1 -> selects buyerTenB (second TEN entrant)
        _runDraw(randomWords);

        uint256 expectedOne = (pool * 15) / 100;
        uint256 expectedFive = (pool * 35) / 100;
        uint256 expectedTen = pool - expectedOne - expectedFive;

        assertEq(buyerOne.balance, expectedOne);
        assertEq(buyerFive.balance, expectedFive);
        assertEq(buyerTenA.balance, 0);
        assertEq(buyerTenB.balance, expectedTen);

        assertEq(lottery.getPoolBalanceETH(), 0);
        assertEq(address(lottery).balance, 0);
        assertEq(uint8(lottery.getLotteryState()), uint8(Lottery.LotteryState.OPEN));
    }

    function test_twoConsecutiveRounds_bothCompleteIndependently() public {
        address roundOneBuyer = makeAddr("roundOneBuyer");
        uint256 priceRoundOne = _buy(roundOneBuyer, Lottery.Tier.ONE);

        _runDraw(new uint256[](3));

        assertEq(roundOneBuyer.balance, priceRoundOne);
        assertEq(lottery.getEntryCount(Lottery.Tier.ONE), 0);

        address roundTwoBuyer = makeAddr("roundTwoBuyer");
        uint256 priceRoundTwo = _buy(roundTwoBuyer, Lottery.Tier.FIVE);
        assertEq(lottery.getPoolBalanceETH(), priceRoundTwo);

        _runDraw(new uint256[](3));

        assertEq(roundTwoBuyer.balance, priceRoundTwo);
        assertEq(lottery.getPoolBalanceETH(), 0);
        assertEq(address(lottery).balance, 0);
    }

    function test_emptyRoundSkipped_thenActiveRoundCompletesNormally() public {
        vm.warp(block.timestamp + INTERVAL);
        feed.updateAnswer(INITIAL_PRICE);
        lottery.performUpkeep("");

        assertEq(uint8(lottery.getLotteryState()), uint8(Lottery.LotteryState.OPEN));

        address buyer = makeAddr("buyer");
        uint256 price = _buy(buyer, Lottery.Tier.TEN);

        _runDraw(new uint256[](3));

        assertEq(buyer.balance, price);
        assertEq(address(lottery).balance, 0);
    }
}
