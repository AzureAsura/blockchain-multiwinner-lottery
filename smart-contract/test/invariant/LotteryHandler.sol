// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Lottery} from "../../src/Lottery.sol";

/// @dev Has no receive/fallback, so payouts to it exercise the claimable fallback path during fuzzing.
contract RejectingActor {
    Lottery private immutable i_lottery;

    constructor(Lottery lottery) {
        i_lottery = lottery;
    }

    function buy(Lottery.Tier tier) external payable {
        i_lottery.buyTicket{value: msg.value}(tier);
    }

    function claim() external {
        i_lottery.claimPrize();
    }
}

/// @notice Drives Lottery through random buy/draw/claim sequences for invariant fuzzing.
contract LotteryHandler is Test {
    Lottery private immutable i_lottery;
    VRFCoordinatorV2_5Mock private immutable i_coordinator;
    MockV3Aggregator private immutable i_feed;
    int256 private immutable i_initialPrice;
    uint256 private immutable i_interval;

    address[] public actors;
    uint256 private s_pendingRequestId;

    constructor(
        Lottery lottery,
        VRFCoordinatorV2_5Mock coordinator,
        MockV3Aggregator feed,
        int256 initialPrice,
        uint256 interval
    ) {
        i_lottery = lottery;
        i_coordinator = coordinator;
        i_feed = feed;
        i_initialPrice = initialPrice;
        i_interval = interval;

        for (uint256 i = 0; i < 4; i++) {
            actors.push(makeAddr(string.concat("actor", vm.toString(i))));
        }
        actors.push(address(new RejectingActor(lottery)));
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function totalClaimable() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += i_lottery.getClaimablePrize(actors[i]);
        }
    }

    function buyTicket(uint256 actorSeed, uint256 tierSeed, uint256 extraSeed) external {
        address buyer = actors[actorSeed % actors.length];
        Lottery.Tier tier = Lottery.Tier(tierSeed % 3);

        i_feed.updateAnswer(i_initialPrice);
        uint256 price = i_lottery.getTicketPriceInWei(tier);
        uint256 total = price + bound(extraSeed, 0, 1 ether);

        if (buyer.code.length > 0) {
            vm.deal(address(this), total);
            try RejectingActor(payable(buyer)).buy{value: total}(tier) {} catch {}
        } else {
            vm.deal(buyer, total);
            vm.prank(buyer);
            try i_lottery.buyTicket{value: total}(tier) {} catch {}
        }
    }

    function performUpkeep() external {
        vm.warp(block.timestamp + i_interval);
        i_feed.updateAnswer(i_initialPrice);

        (bool upkeepNeeded,) = i_lottery.checkUpkeep("");
        if (!upkeepNeeded) return;

        vm.recordLogs();
        try i_lottery.performUpkeep("") {
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i = 0; i < logs.length; i++) {
                if (logs[i].topics[0] == keccak256("DrawRequested(uint256)")) {
                    s_pendingRequestId = uint256(logs[i].topics[1]);
                }
            }
        } catch {}
    }

    function fulfillRandomWords(uint256 word0, uint256 word1, uint256 word2) external {
        if (s_pendingRequestId == 0) return;
        if (i_lottery.getLotteryState() != Lottery.LotteryState.CALCULATING) return;

        uint256[] memory randomWords = new uint256[](3);
        randomWords[0] = word0;
        randomWords[1] = word1;
        randomWords[2] = word2;

        try i_coordinator.fulfillRandomWordsWithOverride(s_pendingRequestId, address(i_lottery), randomWords) {
            s_pendingRequestId = 0;
        } catch {}
    }

    function claimPrize(uint256 actorSeed) external {
        address claimant = actors[actorSeed % actors.length];
        if (claimant.code.length > 0) {
            try RejectingActor(payable(claimant)).claim() {} catch {}
        } else {
            vm.prank(claimant);
            try i_lottery.claimPrize() {} catch {}
        }
    }
}
