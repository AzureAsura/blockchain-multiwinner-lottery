// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {Lottery} from "../src/Lottery.sol";

/// @dev Exposes the internal prize-split math for direct, VRF-free unit and fuzz testing.
contract LotteryHarness is Lottery {
    constructor(
        address vrfCoordinator,
        address priceFeed,
        uint256 interval,
        bytes32 keyHash,
        uint256 subscriptionId,
        uint32 callbackGasLimit,
        uint256 priceFeedStaleAfter
    ) Lottery(vrfCoordinator, priceFeed, interval, keyHash, subscriptionId, callbackGasLimit, priceFeedStaleAfter) {}

    function calculatePrizes(uint256 pool, bool[3] memory tierActive) external pure returns (uint256[3] memory) {
        return _calculatePrizes(pool, tierActive);
    }
}

contract LotteryPrizeMathTest is Test {
    LotteryHarness private harness;

    function setUp() public {
        MockV3Aggregator feed = new MockV3Aggregator(8, 2000e8);
        harness = new LotteryHarness(address(0xBEEF), address(feed), 7 days, keccak256("keyHash"), 1, 500_000, 3 hours);
    }

    function test_calculatePrizes_allThreeActive_matches15_35_50() public view {
        uint256[3] memory prizes = harness.calculatePrizes(100 ether, [true, true, true]);
        assertEq(prizes[0], 15 ether);
        assertEq(prizes[1], 35 ether);
        assertEq(prizes[2], 50 ether);
    }

    function test_calculatePrizes_oneAndFiveActive_matches30_70() public view {
        uint256[3] memory prizes = harness.calculatePrizes(100 ether, [true, true, false]);
        assertEq(prizes[0], 30 ether);
        assertEq(prizes[1], 70 ether);
        assertEq(prizes[2], 0);
    }

    function test_calculatePrizes_oneAndTenActive_matchesApprox23_77() public view {
        uint256[3] memory prizes = harness.calculatePrizes(65 ether, [true, false, true]);
        assertEq(prizes[0], 15 ether);
        assertEq(prizes[2], 50 ether);
        assertEq(prizes[0] + prizes[2], 65 ether);
    }

    function test_calculatePrizes_fiveAndTenActive_matchesApprox41_59() public view {
        uint256[3] memory prizes = harness.calculatePrizes(85 ether, [false, true, true]);
        assertEq(prizes[1], 35 ether);
        assertEq(prizes[2], 50 ether);
        assertEq(prizes[1] + prizes[2], 85 ether);
    }

    function test_calculatePrizes_onlyOneActive_getsFullPool() public view {
        assertEq(harness.calculatePrizes(10 ether, [true, false, false])[0], 10 ether);
    }

    function test_calculatePrizes_onlyFiveActive_getsFullPool() public view {
        assertEq(harness.calculatePrizes(10 ether, [false, true, false])[1], 10 ether);
    }

    function test_calculatePrizes_onlyTenActive_getsFullPool() public view {
        assertEq(harness.calculatePrizes(10 ether, [false, false, true])[2], 10 ether);
    }

    function test_calculatePrizes_noActiveTiers_returnsAllZero() public view {
        uint256[3] memory prizes = harness.calculatePrizes(100 ether, [false, false, false]);
        assertEq(prizes[0], 0);
        assertEq(prizes[1], 0);
        assertEq(prizes[2], 0);
    }

    /// @dev The largest active tier absorbs rounding dust, so the split must always sum to the pool exactly.
    function testFuzz_calculatePrizes_sumAlwaysEqualsPool(uint256 pool, bool active0, bool active1, bool active2)
        public
        view
    {
        pool = bound(pool, 0, 1_000_000_000 ether);
        vm.assume(active0 || active1 || active2);

        uint256[3] memory prizes = harness.calculatePrizes(pool, [active0, active1, active2]);
        assertEq(prizes[0] + prizes[1] + prizes[2], pool);
    }
}
