// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

/// @title HelperConfig
/// @notice Per-network deployment config for Lottery; see NOTE.md for Base Sepolia address provenance.
contract HelperConfig is Script {
    struct NetworkConfig {
        address vrfCoordinator;
        address priceFeed;
        uint256 interval;
        bytes32 keyHash;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        uint256 priceFeedStaleAfter;
    }

    uint256 private constant BASE_SEPOLIA_CHAIN_ID = 84532;

    uint8 private constant MOCK_FEED_DECIMALS = 8;
    int256 private constant MOCK_INITIAL_PRICE = 2000e8;
    uint96 private constant MOCK_BASE_FEE = 0.1 ether;
    uint96 private constant MOCK_GAS_PRICE = 1e9;
    int256 private constant MOCK_WEI_PER_UNIT_LINK = 4e15;

    NetworkConfig private activeNetworkConfig;

    constructor() {
        if (block.chainid == BASE_SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getBaseSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    /// @notice Returns the resolved config for the currently running chain.
    function getConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }

    /// @dev subscriptionId is 0 here; supply a real one via the SUBSCRIPTION_ID env var (see NOTE.md).
    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            vrfCoordinator: 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE,
            priceFeed: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1,
            interval: 5 minutes,
            keyHash: 0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71,
            subscriptionId: 0,
            callbackGasLimit: 500_000,
            priceFeedStaleAfter: 1 hours
        });
    }

    /// @dev VRF_COORDINATOR/PRICE_FEED env vars let a later script reuse mocks from an earlier run.
    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.vrfCoordinator != address(0)) {
            return activeNetworkConfig;
        }

        address coordinator = vm.envOr("VRF_COORDINATOR", address(0));
        address priceFeed = vm.envOr("PRICE_FEED", address(0));
        if (coordinator == address(0) || priceFeed == address(0)) {
            vm.startBroadcast();
            MockV3Aggregator mockPriceFeed = new MockV3Aggregator(MOCK_FEED_DECIMALS, MOCK_INITIAL_PRICE);
            VRFCoordinatorV2_5Mock mockCoordinator =
                new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE, MOCK_WEI_PER_UNIT_LINK);
            vm.stopBroadcast();
            coordinator = address(mockCoordinator);
            priceFeed = address(mockPriceFeed);
        }

        return NetworkConfig({
            vrfCoordinator: coordinator,
            priceFeed: priceFeed,
            interval: 30 seconds,
            keyHash: keccak256("mock keyHash"),
            subscriptionId: 0,
            callbackGasLimit: 500_000,
            priceFeedStaleAfter: 3 hours
        });
    }
}
