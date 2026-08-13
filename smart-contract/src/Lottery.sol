// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";

error Lottery__ZeroAddress();
error Lottery__NotOpen();
error Lottery__InsufficientPayment(uint256 required, uint256 sent);
error Lottery__RefundFailed();
error Lottery__UpkeepNotNeeded();
error Lottery__NothingToClaim();
error Lottery__ClaimFailed();

/// @title Lottery
contract Lottery is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    using PriceConverter for AggregatorV3Interface;

    enum Tier {
        ONE,
        FIVE,
        TEN
    }

    enum LotteryState {
        OPEN,
        CALCULATING
    }

    uint256 private constant TIER_ONE_PRICE_USD = 1e18;
    uint256 private constant TIER_FIVE_PRICE_USD = 5e18;
    uint256 private constant TIER_TEN_PRICE_USD = 10e18;

    uint256 private constant TIER_ONE_WEIGHT = 15;
    uint256 private constant TIER_FIVE_WEIGHT = 35;
    uint256 private constant TIER_TEN_WEIGHT = 50;

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 3;
    uint256 private constant PAYOUT_GAS_STIPEND = 30_000;

    AggregatorV3Interface private immutable i_priceFeed;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint256 private immutable i_priceFeedStaleAfter;

    uint256 private s_round;
    uint256 private s_prizePool;
    uint256 private s_lastDrawTimestamp;
    LotteryState private s_lotteryState;

    mapping(uint256 round => mapping(Tier tier => address[])) private s_entries;
    mapping(address winner => uint256 amount) private s_claimablePrize;

    event TicketPurchased(address indexed buyer, Tier indexed tier, uint256 amountPaid);
    event DrawRequested(uint256 indexed requestId);
    event DrawSkipped();
    event Winner(Tier indexed tier, address indexed winner, uint256 prize);
    event PrizeClaimed(address indexed winner, uint256 amount);

    /// @notice Deploys the lottery with its Chainlink VRF, price feed, and draw configuration.
    constructor(
        address vrfCoordinator,
        address priceFeed,
        uint256 interval,
        bytes32 keyHash,
        uint256 subscriptionId,
        uint32 callbackGasLimit,
        uint256 priceFeedStaleAfter
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        if (priceFeed == address(0)) revert Lottery__ZeroAddress();

        i_priceFeed = AggregatorV3Interface(priceFeed);
        i_interval = interval;
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        i_priceFeedStaleAfter = priceFeedStaleAfter;

        s_lastDrawTimestamp = block.timestamp;
        s_lotteryState = LotteryState.OPEN;
    }

    /// @notice Buys one entry in the given tier, re-pricing on-chain and refunding any overpayment.
    function buyTicket(Tier tier) external payable {
        if (s_lotteryState != LotteryState.OPEN) revert Lottery__NotOpen();

        uint256 ethUsdPrice = i_priceFeed.getEthUsdPrice(i_priceFeedStaleAfter);
        uint256 required = PriceConverter.usdToWei(_tierPriceUsd(tier), ethUsdPrice);
        if (msg.value < required) revert Lottery__InsufficientPayment(required, msg.value);

        s_entries[s_round][tier].push(msg.sender);
        s_prizePool += required;
        emit TicketPurchased(msg.sender, tier, required);

        uint256 refund = msg.value - required;
        if (refund > 0) {
            (bool success,) = msg.sender.call{value: refund}("");
            if (!success) revert Lottery__RefundFailed();
        }
    }

    /// @notice Withdraws the caller's claimable prize balance, if any.
    function claimPrize() external {
        uint256 amount = s_claimablePrize[msg.sender];
        if (amount == 0) revert Lottery__NothingToClaim();

        s_claimablePrize[msg.sender] = 0;
        emit PrizeClaimed(msg.sender, amount);

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert Lottery__ClaimFailed();
    }

    /// @notice Reports whether the draw interval has elapsed while the lottery is open.
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        // forge-lint: disable-next-line(block-timestamp)
        upkeepNeeded = s_lotteryState == LotteryState.OPEN && block.timestamp - s_lastDrawTimestamp >= i_interval;
        performData = "";
    }

    /// @notice Starts a draw, or skips it and resets the timer if nobody entered this round.
    function performUpkeep(bytes calldata) external override {
        if (s_lotteryState != LotteryState.OPEN) revert Lottery__NotOpen();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - s_lastDrawTimestamp < i_interval) revert Lottery__UpkeepNotNeeded();

        if (_totalEntries() == 0) {
            s_lastDrawTimestamp = block.timestamp;
            emit DrawSkipped();
            return;
        }

        s_lotteryState = LotteryState.CALCULATING;

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
        );

        emit DrawRequested(requestId);
    }

    /// @notice Returns the current ETH price, in wei, for a ticket tier.
    function getTicketPriceInWei(Tier tier) external view returns (uint256) {
        uint256 ethUsdPrice = i_priceFeed.getEthUsdPrice(i_priceFeedStaleAfter);
        return PriceConverter.usdToWei(_tierPriceUsd(tier), ethUsdPrice);
    }

    /// @notice Returns the current prize pool balance in wei.
    function getPoolBalanceETH() external view returns (uint256) {
        return s_prizePool;
    }

    /// @notice Returns the current prize pool balance converted to USD.
    function getPoolBalanceUSD() external view returns (uint256) {
        uint256 ethUsdPrice = i_priceFeed.getEthUsdPrice(i_priceFeedStaleAfter);
        return (s_prizePool * ethUsdPrice) / 1e18;
    }

    /// @notice Returns the Unix timestamp at which the next draw becomes eligible.
    function getNextDrawTime() external view returns (uint256) {
        return s_lastDrawTimestamp + i_interval;
    }

    /// @notice Returns the amount of ETH a given address can currently claim.
    function getClaimablePrize(address winner) external view returns (uint256) {
        return s_claimablePrize[winner];
    }

    /// @notice Returns the number of entries in the current round for a tier.
    function getEntryCount(Tier tier) external view returns (uint256) {
        return s_entries[s_round][tier].length;
    }

    /// @notice Returns the current lottery state.
    function getLotteryState() external view returns (LotteryState) {
        return s_lotteryState;
    }

    function _tierPriceUsd(Tier tier) private pure returns (uint256) {
        if (tier == Tier.ONE) return TIER_ONE_PRICE_USD;
        if (tier == Tier.FIVE) return TIER_FIVE_PRICE_USD;
        return TIER_TEN_PRICE_USD;
    }

    function _totalEntries() private view returns (uint256) {
        return s_entries[s_round][Tier.ONE].length + s_entries[s_round][Tier.FIVE].length
            + s_entries[s_round][Tier.TEN].length;
    }

    /// @dev Splits `pool` across active tiers by weight; the largest active tier absorbs all rounding dust.
    function _calculatePrizes(uint256 pool, bool[3] memory tierActive)
        internal
        pure
        returns (uint256[3] memory prizes)
    {
        uint256[3] memory weights = [TIER_ONE_WEIGHT, TIER_FIVE_WEIGHT, TIER_TEN_WEIGHT];
        uint256 totalActiveWeight;
        uint256 largestIndex;
        uint256 largestWeight;

        for (uint256 i = 0; i < 3; i++) {
            if (!tierActive[i]) continue;
            totalActiveWeight += weights[i];
            if (weights[i] > largestWeight) {
                largestWeight = weights[i];
                largestIndex = i;
            }
        }

        if (totalActiveWeight == 0) return prizes;

        uint256 allocated;
        for (uint256 i = 0; i < 3; i++) {
            if (!tierActive[i] || i == largestIndex) continue;
            prizes[i] = (pool * weights[i]) / totalActiveWeight;
            allocated += prizes[i];
        }
        prizes[largestIndex] = pool - allocated;
    }

    /// @dev Picks one winner per active tier, splits the pool, resets the round, then pays out.
    function fulfillRandomWords(uint256, uint256[] calldata randomWords) internal override {
        uint256 round = s_round;
        uint256 pool = s_prizePool;

        bool[3] memory tierActive;
        address[3] memory winners;
        for (uint256 i = 0; i < 3; i++) {
            uint256 count = s_entries[round][Tier(i)].length;
            if (count == 0) continue;
            tierActive[i] = true;
            winners[i] = s_entries[round][Tier(i)][randomWords[i] % count];
        }

        uint256[3] memory prizes = _calculatePrizes(pool, tierActive);

        s_prizePool = 0;
        s_round = round + 1;
        s_lastDrawTimestamp = block.timestamp;
        s_lotteryState = LotteryState.OPEN;

        for (uint256 i = 0; i < 3; i++) {
            if (tierActive[i]) emit Winner(Tier(i), winners[i], prizes[i]);
        }

        for (uint256 i = 0; i < 3; i++) {
            if (tierActive[i] && prizes[i] > 0) _payout(winners[i], prizes[i]);
        }
    }

    /// @dev Falls back to a claimable balance instead of reverting, so one bad winner can't block the draw.
    function _payout(address winner, uint256 prize) private {
        (bool success,) = winner.call{value: prize, gas: PAYOUT_GAS_STIPEND}("");
        if (!success) s_claimablePrize[winner] += prize;
    }
}
