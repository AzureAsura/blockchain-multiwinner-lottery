// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {PriceConverter, Lottery__InvalidPrice, Lottery__StalePrice} from "../src/PriceConverter.sol";

contract PriceConverterTest is Test {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant INITIAL_PRICE = 2000e8; // $2000/ETH
    uint256 private constant STALE_AFTER = 3 hours;

    MockV3Aggregator private feed;

    function setUp() public {
        feed = new MockV3Aggregator(FEED_DECIMALS, INITIAL_PRICE);
    }

    /// @dev Wrapper so vm.expectRevert latches onto this call, not the inlined feed staticcall.
    function callGetEthUsdPrice() external view returns (uint256) {
        return PriceConverter.getEthUsdPrice(feed, STALE_AFTER);
    }

    function test_getEthUsdPrice_normalizesTo18Decimals() public view {
        uint256 price = PriceConverter.getEthUsdPrice(feed, STALE_AFTER);
        assertEq(price, 2000e18);
    }

    function test_getEthUsdPrice_revertsOnZeroPrice() public {
        feed.updateAnswer(0);
        vm.expectRevert(Lottery__InvalidPrice.selector);
        this.callGetEthUsdPrice();
    }

    function test_getEthUsdPrice_revertsOnNegativePrice() public {
        feed.updateAnswer(-1);
        vm.expectRevert(Lottery__InvalidPrice.selector);
        this.callGetEthUsdPrice();
    }

    function test_getEthUsdPrice_revertsOnStalePrice() public {
        vm.warp(block.timestamp + STALE_AFTER + 1);
        vm.expectRevert(Lottery__StalePrice.selector);
        this.callGetEthUsdPrice();
    }

    function test_getEthUsdPrice_succeedsAtExactStaleBoundary() public {
        vm.warp(block.timestamp + STALE_AFTER);
        uint256 price = PriceConverter.getEthUsdPrice(feed, STALE_AFTER);
        assertEq(price, 2000e18);
    }

    function test_usdToWei_matchesManualCalculation() public pure {
        // $5 at $2000/ETH => 0.0025 ETH
        uint256 weiAmount = PriceConverter.usdToWei(5e18, 2000e18);
        assertEq(weiAmount, 0.0025 ether);
    }

    function testFuzz_getEthUsdPrice_revertsOnNonPositiveAnswer(int256 answer) public {
        answer = bound(answer, type(int256).min, 0);
        feed.updateAnswer(answer);
        vm.expectRevert(Lottery__InvalidPrice.selector);
        this.callGetEthUsdPrice();
    }

    function testFuzz_getEthUsdPrice_revertsWhenOlderThanStaleAfter(uint256 elapsed) public {
        elapsed = bound(elapsed, STALE_AFTER + 1, 365 days);
        vm.warp(block.timestamp + elapsed);
        vm.expectRevert(Lottery__StalePrice.selector);
        this.callGetEthUsdPrice();
    }

    /// @dev Rounding loss must stay under one USD unit of price precision.
    function testFuzz_usdToWei_roundTripPrecision(uint256 usdAmount18, uint256 ethUsdPrice18) public pure {
        usdAmount18 = bound(usdAmount18, 1, 1_000_000e18);
        ethUsdPrice18 = bound(ethUsdPrice18, 1e18, 100_000e18); // $1 to $100k per ETH

        uint256 weiAmount = PriceConverter.usdToWei(usdAmount18, ethUsdPrice18);
        uint256 recoveredUsd = (weiAmount * ethUsdPrice18) / 1e18;

        assertLe(recoveredUsd, usdAmount18);
        assertLe(usdAmount18 - recoveredUsd, ethUsdPrice18 / 1e18 + 1);
    }
}
