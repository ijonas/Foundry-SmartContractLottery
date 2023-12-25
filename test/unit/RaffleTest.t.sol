// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    // Events
    event EnterRaffle(address indexed player);

    modifier PlayerEnteredRaffle() {
        vm.prank(PLAYER);

        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    Raffle raffle;
    HelperConfig helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address linkToken;

    address public PLAYER = makeAddr("PLAYER");
    uint256 public constant STARTING_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();

        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            linkToken,

        ) = helperConfig.s_activeNetworkConfig();
        vm.deal(PLAYER, STARTING_BALANCE);
    }

    function testRaffleInitialisedInRaffleOpenState() external view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);

        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle{value: 0 ether}();
    }

    function testRaffleRevertsWhenYouPayEnough() public {
        vm.prank(PLAYER);

        raffle.enterRaffle{value: entranceFee}();

        address payable player = raffle.getPlayer(0);
        assertEq(player, PLAYER);
    }

    function testEmitsEventOnEnterRaffle() public {
        vm.prank(PLAYER);

        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnterRaffle(PLAYER);

        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterRaffleWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);

        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepFalseIfNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepFalseIfNotOpen() public {
        vm.prank(PLAYER);

        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepFalseIfNotEnoughPlayers() public {
        vm.prank(PLAYER);

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepTrueWhenAllParamsWell() public PlayerEnteredRaffle {
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assertEq(upkeepNeeded, true);
    }

    function testPerformUpkeepOnlyIfCheckUpkeepTrue()
        public
        PlayerEnteredRaffle
    {
        raffle.performUpkeep("");
        Raffle.RaffleState currentState = raffle.getRaffleState();
        assert(currentState == Raffle.RaffleState.CALCULATING_WINNER);
    }

    function testPerformUpkeepRevertsIfCheckUpkeepFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                "Upkeep not needed. Check upkeep first."
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        PlayerEnteredRaffle
    {
        // Arrange

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // Assert
        assert(uint256(requestId) > 0);
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public PlayerEnteredRaffle skipFork {
        // Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
        // Act

        // Assert
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        PlayerEnteredRaffle
        skipFork
    {
        // Arrange
        uint256 startingIndex = 1;
        uint256 additionalEntrants = 5;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 previousLastTimestamp = raffle.getLastTimestamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getPlayers().length == 0);
        assert(raffle.getLastTimestamp() != previousLastTimestamp);
        assertEq(
            raffle.getRecentWinner().balance,
            STARTING_BALANCE + prize - entranceFee
        );
    }
}
