// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Lottery, Lottery__NotOpen} from "../src/Lottery.sol";

/// @dev Buys a ticket, then tries to re-enter buyTicket from receive() using the refunded ETH.
contract ReentrantBuyer {
    Lottery private immutable i_lottery;
    Lottery.Tier private s_tier;
    bool private s_reentered;
    uint256 public reentryAttempts;

    constructor(Lottery lottery) {
        i_lottery = lottery;
    }

    function buy(Lottery.Tier tier) external payable {
        s_tier = tier;
        i_lottery.buyTicket{value: msg.value}(tier);
    }

    receive() external payable {
        if (s_reentered) return;
        s_reentered = true;
        reentryAttempts++;
        i_lottery.buyTicket{value: msg.value}(s_tier);
    }
}

/// @notice Tests mapped directly to attack vectors researched in docs/ATTACK.md.
contract LotterySecurityTest is Test {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant INITIAL_PRICE = 2000e8;
    uint256 private constant STALE_AFTER = 3 hours;
    uint256 private constant INTERVAL = 7 days;
    address private constant VRF_COORDINATOR = address(0xBEEF);
    bytes32 private constant KEY_HASH = keccak256("keyHash");
    uint256 private constant SUB_ID = 1;
    uint32 private constant CALLBACK_GAS_LIMIT = 500_000;
    uint96 private constant MOCK_BASE_FEE = 0.1 ether;
    uint96 private constant MOCK_GAS_PRICE = 1e9;
    int256 private constant MOCK_WEI_PER_UNIT_LINK = 4e15;

    MockV3Aggregator private feed;
    Lottery private lottery;

    function setUp() public {
        feed = new MockV3Aggregator(FEED_DECIMALS, INITIAL_PRICE);
        lottery =
            new Lottery(VRF_COORDINATOR, address(feed), INTERVAL, KEY_HASH, SUB_ID, CALLBACK_GAS_LIMIT, STALE_AFTER);
    }

    function _deployWithMockCoordinator(uint256 fundAmount)
        private
        returns (Lottery newLottery, VRFCoordinatorV2_5Mock coordinator, uint256 subId)
    {
        coordinator = new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE, MOCK_WEI_PER_UNIT_LINK);
        subId = coordinator.createSubscription();

        newLottery = new Lottery(
            address(coordinator), address(feed), INTERVAL, KEY_HASH, subId, CALLBACK_GAS_LIMIT, STALE_AFTER
        );

        coordinator.addConsumer(subId, address(newLottery));
        if (fundAmount > 0) {
            coordinator.fundSubscriptionWithNative{value: fundAmount}(subId);
        }
    }

    function _buyAndWarp(Lottery target, address buyer, Lottery.Tier tier) private returns (uint256 price) {
        price = target.getTicketPriceInWei(tier);
        vm.deal(buyer, price);
        vm.prank(buyer);
        target.buyTicket{value: price}(tier);
        vm.warp(block.timestamp + INTERVAL);
        feed.updateAnswer(INITIAL_PRICE);
    }

    // ATTACK.md #1: request-fulfillment window gaming.
    function test_buyTicket_revertsAfterRealPerformUpkeep_beforeFulfillment() public {
        (Lottery newLottery, VRFCoordinatorV2_5Mock coordinator,) = _deployWithMockCoordinator(1 ether);
        address firstBuyer = makeAddr("firstBuyer");
        _buyAndWarp(newLottery, firstBuyer, Lottery.Tier.ONE);

        newLottery.performUpkeep("");
        assertEq(uint8(newLottery.getLotteryState()), uint8(Lottery.LotteryState.CALCULATING));

        address lateBuyer = makeAddr("lateBuyer");
        uint256 price = newLottery.getTicketPriceInWei(Lottery.Tier.ONE);
        vm.deal(lateBuyer, price);
        vm.prank(lateBuyer);
        vm.expectRevert(Lottery__NotOpen.selector);
        newLottery.buyTicket{value: price}(Lottery.Tier.ONE);

        coordinator.fulfillRandomWordsWithOverride(1, address(newLottery), new uint256[](3));
    }

    // ATTACK.md #1: access control on the VRF callback.
    function test_rawFulfillRandomWords_revertsWhenCalledByNonCoordinator() public {
        uint256[] memory randomWords = new uint256[](3);
        vm.expectRevert(
            abi.encodeWithSelector(
                VRFConsumerBaseV2Plus.OnlyCoordinatorCanFulfill.selector, address(this), VRF_COORDINATOR
            )
        );
        lottery.rawFulfillRandomWords(1, randomWords);
    }

    // ATTACK.md #19: unbounded loop / gas-limit DoS from a large entry count.
    function test_fulfillRandomWords_gasCostIndependentOfEntryCount() public {
        (Lottery lotteryFew, VRFCoordinatorV2_5Mock coordFew,) = _deployWithMockCoordinator(1 ether);
        address fewBuyer = makeAddr("fewBuyer");
        _buyAndWarp(lotteryFew, fewBuyer, Lottery.Tier.ONE);
        lotteryFew.performUpkeep("");

        uint256 gasBeforeFew = gasleft();
        coordFew.fulfillRandomWordsWithOverride(1, address(lotteryFew), new uint256[](3));
        uint256 gasUsedFew = gasBeforeFew - gasleft();

        (Lottery lotteryMany, VRFCoordinatorV2_5Mock coordMany,) = _deployWithMockCoordinator(1 ether);
        uint256 price = lotteryMany.getTicketPriceInWei(Lottery.Tier.ONE);
        address manyBuyer = makeAddr("manyBuyer");
        vm.deal(manyBuyer, price * 400);
        vm.startPrank(manyBuyer);
        for (uint256 i = 0; i < 400; i++) {
            lotteryMany.buyTicket{value: price}(Lottery.Tier.ONE);
        }
        vm.stopPrank();
        vm.warp(block.timestamp + INTERVAL);
        feed.updateAnswer(INITIAL_PRICE);
        lotteryMany.performUpkeep("");

        uint256 gasBeforeMany = gasleft();
        coordMany.fulfillRandomWordsWithOverride(1, address(lotteryMany), new uint256[](3));
        uint256 gasUsedMany = gasBeforeMany - gasleft();

        assertApproxEqAbs(gasUsedFew, gasUsedMany, 10_000);
    }

    // ATTACK.md #4: VRF subscription running dry — see NOTE.md for why this reflects real mock behavior.
    function test_draw_getsStuckInCalculating_ifSubscriptionRunsDryBeforeFulfillment() public {
        (Lottery newLottery, VRFCoordinatorV2_5Mock coordinator,) = _deployWithMockCoordinator(0);
        address buyer = makeAddr("buyer");
        _buyAndWarp(newLottery, buyer, Lottery.Tier.ONE);

        newLottery.performUpkeep("");
        assertEq(uint8(newLottery.getLotteryState()), uint8(Lottery.LotteryState.CALCULATING));

        vm.expectRevert();
        coordinator.fulfillRandomWordsWithOverride(1, address(newLottery), new uint256[](3));

        assertEq(uint8(newLottery.getLotteryState()), uint8(Lottery.LotteryState.CALCULATING));
    }

    // ATTACK.md #15: reentrancy through the buyTicket refund.
    function test_buyTicket_reentrantBuyDuringRefund_isJustALegitimateSecondPurchase() public {
        ReentrantBuyer buyer = new ReentrantBuyer(lottery);
        uint256 price = lottery.getTicketPriceInWei(Lottery.Tier.ONE);

        buyer.buy{value: price * 2}(Lottery.Tier.ONE);

        assertEq(buyer.reentryAttempts(), 1);
        assertEq(lottery.getEntryCount(Lottery.Tier.ONE), 2);
        assertEq(lottery.getPoolBalanceETH(), price * 2);
        assertEq(address(buyer).balance, 0);
    }
}
