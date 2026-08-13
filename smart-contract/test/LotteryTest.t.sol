// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Lottery, Lottery__ZeroAddress, Lottery__NotOpen, Lottery__InsufficientPayment} from "../src/Lottery.sol";
import {Lottery__RefundFailed, Lottery__UpkeepNotNeeded} from "../src/Lottery.sol";
import {Lottery__NothingToClaim, Lottery__ClaimFailed} from "../src/Lottery.sol";
import {Lottery__StalePrice} from "../src/PriceConverter.sol";

/// @dev Has no receive/fallback, so any plain ETH transfer to it reverts.
contract RejectingReceiver {
    Lottery private immutable i_lottery;

    constructor(Lottery lottery) {
        i_lottery = lottery;
    }

    function buy(Lottery.Tier tier) external payable {
        i_lottery.buyTicket{value: msg.value}(tier);
    }
}

/// @dev Tries to re-enter claimPrize() from receive(); the reentrant call must fail without reverting the outer one.
contract ReentrantClaimer {
    Lottery private immutable i_lottery;
    uint256 public totalReceived;
    uint256 public reentryCallSucceeded;

    constructor(Lottery lottery) {
        i_lottery = lottery;
    }

    receive() external payable {
        totalReceived += msg.value;
        (bool success,) = address(i_lottery).call(abi.encodeWithSignature("claimPrize()"));
        if (success) reentryCallSucceeded++;
    }

    function claim() external {
        i_lottery.claimPrize();
    }
}

contract LotteryTest is Test {
    using stdStorage for StdStorage;

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
        lottery = _deploy(address(feed));
    }

    function _deploy(address priceFeed) private returns (Lottery) {
        return new Lottery(VRF_COORDINATOR, priceFeed, INTERVAL, KEY_HASH, SUB_ID, CALLBACK_GAS_LIMIT, STALE_AFTER);
    }

    function _forceState(Lottery.LotteryState state) private {
        stdstore.target(address(lottery)).sig(lottery.getLotteryState.selector).checked_write(uint256(state));
    }

    /// @dev Sets a claimable balance directly, bypassing the draw mechanics, and funds the contract to match.
    function _setClaimable(Lottery target, address claimer, uint256 amount) private {
        stdstore.target(address(target)).sig(target.getClaimablePrize.selector).with_key(claimer).checked_write(amount);
        vm.deal(address(target), address(target).balance + amount);
    }

    /// @dev VRF_COORDINATOR is a dummy address; a real mock is needed for tests where performUpkeep actually calls it.
    function _deployWithMockCoordinator()
        private
        returns (Lottery newLottery, VRFCoordinatorV2_5Mock coordinator, uint256 subId)
    {
        coordinator = new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE, MOCK_WEI_PER_UNIT_LINK);
        subId = coordinator.createSubscription();

        newLottery = new Lottery(
            address(coordinator), address(feed), INTERVAL, KEY_HASH, subId, CALLBACK_GAS_LIMIT, STALE_AFTER
        );

        coordinator.addConsumer(subId, address(newLottery));
        coordinator.fundSubscriptionWithNative{value: 10 ether}(subId);
    }

    /// @dev Warps past the interval and triggers the draw; requestId is always 1 on a fresh coordinator.
    function _warpAndPerformUpkeep(Lottery newLottery) private {
        vm.warp(block.timestamp + INTERVAL);
        newLottery.performUpkeep("");
    }

    function test_constructor_revertsOnZeroPriceFeed() public {
        vm.expectRevert(Lottery__ZeroAddress.selector);
        _deploy(address(0));
    }

    function test_constructor_revertsOnZeroCoordinator() public {
        vm.expectRevert(VRFConsumerBaseV2Plus.ZeroAddress.selector);
        new Lottery(address(0), address(feed), INTERVAL, KEY_HASH, SUB_ID, CALLBACK_GAS_LIMIT, STALE_AFTER);
    }

    function test_initialState_isOpen() public view {
        assertEq(uint8(lottery.getLotteryState()), uint8(Lottery.LotteryState.OPEN));
    }

    function test_initialState_poolIsEmpty() public view {
        assertEq(lottery.getPoolBalanceETH(), 0);
        assertEq(lottery.getPoolBalanceUSD(), 0);
    }

    function test_initialState_noEntries() public view {
        assertEq(lottery.getEntryCount(Lottery.Tier.ONE), 0);
        assertEq(lottery.getEntryCount(Lottery.Tier.FIVE), 0);
        assertEq(lottery.getEntryCount(Lottery.Tier.TEN), 0);
    }

    function test_initialState_nothingClaimable() public view {
        assertEq(lottery.getClaimablePrize(address(this)), 0);
    }

    function test_getNextDrawTime_equalsDeployTimePlusInterval() public view {
        assertEq(lottery.getNextDrawTime(), block.timestamp + INTERVAL);
    }

    function test_getTicketPriceInWei_matchesExpectedConversion() public view {
        assertEq(lottery.getTicketPriceInWei(Lottery.Tier.ONE), 0.0005 ether);
        assertEq(lottery.getTicketPriceInWei(Lottery.Tier.FIVE), 0.0025 ether);
        assertEq(lottery.getTicketPriceInWei(Lottery.Tier.TEN), 0.005 ether);
    }

    function test_getTicketPriceInWei_revertsOnStalePrice() public {
        vm.warp(block.timestamp + STALE_AFTER + 1);
        vm.expectRevert(Lottery__StalePrice.selector);
        lottery.getTicketPriceInWei(Lottery.Tier.ONE);
    }

    function test_getTicketPriceInWei_succeedsAtExactStaleBoundary() public {
        vm.warp(block.timestamp + STALE_AFTER);
        assertEq(lottery.getTicketPriceInWei(Lottery.Tier.ONE), 0.0005 ether);
    }

    function test_buyTicket_exactPayment_registersEntryAndUpdatesPool() public {
        uint256 price = lottery.getTicketPriceInWei(Lottery.Tier.FIVE);
        address buyer = makeAddr("buyer");
        vm.deal(buyer, price);

        vm.prank(buyer);
        lottery.buyTicket{value: price}(Lottery.Tier.FIVE);

        assertEq(lottery.getEntryCount(Lottery.Tier.FIVE), 1);
        assertEq(lottery.getPoolBalanceETH(), price);
        assertEq(buyer.balance, 0);
    }

    function test_buyTicket_overpayment_refundsExcess() public {
        uint256 price = lottery.getTicketPriceInWei(Lottery.Tier.ONE);
        uint256 extra = 0.01 ether;
        address buyer = makeAddr("buyer");
        vm.deal(buyer, price + extra);

        vm.prank(buyer);
        lottery.buyTicket{value: price + extra}(Lottery.Tier.ONE);

        assertEq(buyer.balance, extra);
        assertEq(lottery.getPoolBalanceETH(), price);
    }

    function test_buyTicket_revertsOnInsufficientPayment() public {
        uint256 price = lottery.getTicketPriceInWei(Lottery.Tier.TEN);
        vm.expectRevert(abi.encodeWithSelector(Lottery__InsufficientPayment.selector, price, price - 1));
        lottery.buyTicket{value: price - 1}(Lottery.Tier.TEN);
    }

    function test_buyTicket_revertsWhenNotOpen() public {
        _forceState(Lottery.LotteryState.CALCULATING);
        uint256 price = lottery.getTicketPriceInWei(Lottery.Tier.ONE);

        vm.expectRevert(Lottery__NotOpen.selector);
        lottery.buyTicket{value: price}(Lottery.Tier.ONE);
    }

    function test_buyTicket_sameWalletMultiplePurchases_getsMultipleEntries() public {
        uint256 price = lottery.getTicketPriceInWei(Lottery.Tier.ONE);
        address buyer = makeAddr("buyer");
        vm.deal(buyer, price * 3);

        vm.startPrank(buyer);
        lottery.buyTicket{value: price}(Lottery.Tier.ONE);
        lottery.buyTicket{value: price}(Lottery.Tier.ONE);
        lottery.buyTicket{value: price}(Lottery.Tier.ONE);
        vm.stopPrank();

        assertEq(lottery.getEntryCount(Lottery.Tier.ONE), 3);
    }

    function test_buyTicket_emitsTicketPurchased() public {
        uint256 price = lottery.getTicketPriceInWei(Lottery.Tier.FIVE);
        address buyer = makeAddr("buyer");
        vm.deal(buyer, price);

        vm.expectEmit(true, true, false, true, address(lottery));
        emit Lottery.TicketPurchased(buyer, Lottery.Tier.FIVE, price);

        vm.prank(buyer);
        lottery.buyTicket{value: price}(Lottery.Tier.FIVE);
    }

    function test_buyTicket_revertsOnRefundFailure() public {
        RejectingReceiver rejector = new RejectingReceiver(lottery);
        uint256 price = lottery.getTicketPriceInWei(Lottery.Tier.ONE);

        vm.expectRevert(Lottery__RefundFailed.selector);
        rejector.buy{value: price + 1}(Lottery.Tier.ONE);
    }

    function testFuzz_buyTicket_overpaymentIsRefundedExactly(uint256 extra) public {
        extra = bound(extra, 1, 100 ether);
        uint256 price = lottery.getTicketPriceInWei(Lottery.Tier.FIVE);
        address buyer = makeAddr("buyer");
        vm.deal(buyer, price + extra);

        vm.prank(buyer);
        lottery.buyTicket{value: price + extra}(Lottery.Tier.FIVE);

        assertEq(buyer.balance, extra);
        assertEq(lottery.getPoolBalanceETH(), price);
    }

    function test_checkUpkeep_falseBeforeInterval() public view {
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_checkUpkeep_trueAfterInterval() public {
        vm.warp(block.timestamp + INTERVAL);
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function test_checkUpkeep_falseWhenCalculating() public {
        _forceState(Lottery.LotteryState.CALCULATING);
        vm.warp(block.timestamp + INTERVAL);

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_performUpkeep_revertsBeforeInterval() public {
        vm.expectRevert(Lottery__UpkeepNotNeeded.selector);
        lottery.performUpkeep("");
    }

    function test_performUpkeep_revertsWhenNotOpen() public {
        _forceState(Lottery.LotteryState.CALCULATING);
        vm.warp(block.timestamp + INTERVAL);

        vm.expectRevert(Lottery__NotOpen.selector);
        lottery.performUpkeep("");
    }

    function test_performUpkeep_skipsDrawWhenNoEntries() public {
        vm.warp(block.timestamp + INTERVAL);
        uint256 drawTime = block.timestamp;

        vm.expectEmit(false, false, false, false, address(lottery));
        emit Lottery.DrawSkipped();
        lottery.performUpkeep("");

        assertEq(uint8(lottery.getLotteryState()), uint8(Lottery.LotteryState.OPEN));
        assertEq(lottery.getNextDrawTime(), drawTime + INTERVAL);
    }

    function test_performUpkeep_requestsVrfWhenEntriesExist() public {
        (Lottery newLottery,,) = _deployWithMockCoordinator();
        uint256 price = newLottery.getTicketPriceInWei(Lottery.Tier.ONE);
        vm.deal(address(this), price);
        newLottery.buyTicket{value: price}(Lottery.Tier.ONE);

        vm.warp(block.timestamp + INTERVAL);

        vm.expectEmit(true, false, false, false, address(newLottery));
        emit Lottery.DrawRequested(1);
        newLottery.performUpkeep("");

        assertEq(uint8(newLottery.getLotteryState()), uint8(Lottery.LotteryState.CALCULATING));
    }

    function test_fulfillRandomWords_singleTierWinner_getsFullPool() public {
        (Lottery newLottery, VRFCoordinatorV2_5Mock coordinator,) = _deployWithMockCoordinator();
        address buyer = makeAddr("buyer");
        uint256 price = newLottery.getTicketPriceInWei(Lottery.Tier.ONE);
        vm.deal(buyer, price);
        vm.prank(buyer);
        newLottery.buyTicket{value: price}(Lottery.Tier.ONE);

        _warpAndPerformUpkeep(newLottery);

        uint256[] memory randomWords = new uint256[](3);
        coordinator.fulfillRandomWordsWithOverride(1, address(newLottery), randomWords);

        assertEq(buyer.balance, price);
        assertEq(newLottery.getPoolBalanceETH(), 0);
        assertEq(address(newLottery).balance, 0);
        assertEq(uint8(newLottery.getLotteryState()), uint8(Lottery.LotteryState.OPEN));
        assertEq(newLottery.getEntryCount(Lottery.Tier.ONE), 0);
    }

    function test_fulfillRandomWords_twoTiersActive_splitsByWeight() public {
        (Lottery newLottery, VRFCoordinatorV2_5Mock coordinator,) = _deployWithMockCoordinator();
        address buyerOne = makeAddr("buyerOne");
        address buyerFive = makeAddr("buyerFive");
        uint256 priceOne = newLottery.getTicketPriceInWei(Lottery.Tier.ONE);
        uint256 priceFive = newLottery.getTicketPriceInWei(Lottery.Tier.FIVE);
        vm.deal(buyerOne, priceOne);
        vm.deal(buyerFive, priceFive);
        vm.prank(buyerOne);
        newLottery.buyTicket{value: priceOne}(Lottery.Tier.ONE);
        vm.prank(buyerFive);
        newLottery.buyTicket{value: priceFive}(Lottery.Tier.FIVE);

        _warpAndPerformUpkeep(newLottery);

        uint256[] memory randomWords = new uint256[](3);
        coordinator.fulfillRandomWordsWithOverride(1, address(newLottery), randomWords);

        uint256 pool = priceOne + priceFive;
        assertEq(buyerOne.balance, (pool * 15) / 50);
        assertEq(buyerFive.balance, pool - (pool * 15) / 50);
        assertEq(buyerOne.balance + buyerFive.balance, pool);
        assertEq(address(newLottery).balance, 0);
    }

    function test_fulfillRandomWords_selectsWinnerByRandomWordModulo() public {
        (Lottery newLottery, VRFCoordinatorV2_5Mock coordinator,) = _deployWithMockCoordinator();
        address buyerA = makeAddr("buyerA");
        address buyerB = makeAddr("buyerB");
        uint256 price = newLottery.getTicketPriceInWei(Lottery.Tier.ONE);
        vm.deal(buyerA, price);
        vm.deal(buyerB, price);
        vm.prank(buyerA);
        newLottery.buyTicket{value: price}(Lottery.Tier.ONE);
        vm.prank(buyerB);
        newLottery.buyTicket{value: price}(Lottery.Tier.ONE);

        _warpAndPerformUpkeep(newLottery);

        uint256[] memory randomWords = new uint256[](3);
        randomWords[0] = 7; // 7 % 2 == 1 -> second entrant (buyerB)
        coordinator.fulfillRandomWordsWithOverride(1, address(newLottery), randomWords);

        assertEq(buyerA.balance, 0);
        assertEq(buyerB.balance, price * 2);
    }

    function test_fulfillRandomWords_winnerRejectsEth_fallsBackToClaimable() public {
        (Lottery newLottery, VRFCoordinatorV2_5Mock coordinator,) = _deployWithMockCoordinator();
        RejectingReceiver rejector = new RejectingReceiver(newLottery);
        uint256 price = newLottery.getTicketPriceInWei(Lottery.Tier.ONE);
        rejector.buy{value: price}(Lottery.Tier.ONE);

        _warpAndPerformUpkeep(newLottery);

        uint256[] memory randomWords = new uint256[](3);
        coordinator.fulfillRandomWordsWithOverride(1, address(newLottery), randomWords);

        assertEq(address(rejector).balance, 0);
        assertEq(newLottery.getClaimablePrize(address(rejector)), price);
        assertEq(uint8(newLottery.getLotteryState()), uint8(Lottery.LotteryState.OPEN));
    }

    function test_fulfillRandomWords_newRoundAcceptsPurchasesAgain() public {
        (Lottery newLottery, VRFCoordinatorV2_5Mock coordinator,) = _deployWithMockCoordinator();
        address buyer = makeAddr("buyer");
        uint256 price = newLottery.getTicketPriceInWei(Lottery.Tier.ONE);
        vm.deal(buyer, price);
        vm.prank(buyer);
        newLottery.buyTicket{value: price}(Lottery.Tier.ONE);

        _warpAndPerformUpkeep(newLottery);
        uint256[] memory randomWords = new uint256[](3);
        coordinator.fulfillRandomWordsWithOverride(1, address(newLottery), randomWords);

        feed.updateAnswer(INITIAL_PRICE);
        address secondBuyer = makeAddr("secondBuyer");
        vm.deal(secondBuyer, price);
        vm.prank(secondBuyer);
        newLottery.buyTicket{value: price}(Lottery.Tier.ONE);

        assertEq(newLottery.getEntryCount(Lottery.Tier.ONE), 1);
        assertEq(newLottery.getPoolBalanceETH(), price);
    }

    function test_claimPrize_transfersAndZeroesBalance() public {
        address claimer = makeAddr("claimer");
        _setClaimable(lottery, claimer, 1 ether);

        vm.prank(claimer);
        lottery.claimPrize();

        assertEq(claimer.balance, 1 ether);
        assertEq(lottery.getClaimablePrize(claimer), 0);
    }

    function test_claimPrize_revertsWhenNothingToClaim() public {
        vm.expectRevert(Lottery__NothingToClaim.selector);
        lottery.claimPrize();
    }

    function test_claimPrize_revertsOnSecondClaim() public {
        address claimer = makeAddr("claimer");
        _setClaimable(lottery, claimer, 1 ether);

        vm.startPrank(claimer);
        lottery.claimPrize();

        vm.expectRevert(Lottery__NothingToClaim.selector);
        lottery.claimPrize();
        vm.stopPrank();
    }

    function test_claimPrize_emitsPrizeClaimed() public {
        address claimer = makeAddr("claimer");
        _setClaimable(lottery, claimer, 1 ether);

        vm.expectEmit(true, false, false, true, address(lottery));
        emit Lottery.PrizeClaimed(claimer, 1 ether);

        vm.prank(claimer);
        lottery.claimPrize();
    }

    function test_claimPrize_revertsOnTransferFailure() public {
        RejectingReceiver rejector = new RejectingReceiver(lottery);
        _setClaimable(lottery, address(rejector), 1 ether);

        vm.prank(address(rejector));
        vm.expectRevert(Lottery__ClaimFailed.selector);
        lottery.claimPrize();

        assertEq(lottery.getClaimablePrize(address(rejector)), 1 ether);
    }

    function test_claimPrize_reentrancyCannotDoubleClaim() public {
        ReentrantClaimer attacker = new ReentrantClaimer(lottery);
        _setClaimable(lottery, address(attacker), 1 ether);

        attacker.claim();

        assertEq(attacker.totalReceived(), 1 ether);
        assertEq(attacker.reentryCallSucceeded(), 0);
        assertEq(lottery.getClaimablePrize(address(attacker)), 0);
    }
}
