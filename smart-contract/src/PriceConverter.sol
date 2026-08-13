// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

uint256 constant PRICE_FEED_DECIMALS = 8;
uint256 constant TARGET_DECIMALS = 18;

error Lottery__InvalidPrice();
error Lottery__StalePrice();

/// @title PriceConverter
library PriceConverter {
    /// @notice Returns the latest ETH/USD price scaled to 18 decimals.
    function getEthUsdPrice(AggregatorV3Interface feed, uint256 staleAfter) internal view returns (uint256 price) {
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();

        if (answer <= 0) revert Lottery__InvalidPrice();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - updatedAt > staleAfter) revert Lottery__StalePrice();

        // forge-lint: disable-next-line(unsafe-typecast)
        price = uint256(answer) * 10 ** (TARGET_DECIMALS - PRICE_FEED_DECIMALS);
    }

    /// @notice Converts a USD amount (18 decimals) into its wei equivalent at a given ETH/USD price.
    function usdToWei(uint256 usdAmount18, uint256 ethUsdPrice18) internal pure returns (uint256 weiAmount) {
        weiAmount = (usdAmount18 * 10 ** TARGET_DECIMALS) / ethUsdPrice18;
    }
}
