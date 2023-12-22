// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/dev/ConfirmedOwner.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title Raffle
 * @author Ijonas Kisselbach
 * @notice This contract is used to create a raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is
    VRFConsumerBaseV2,
    ConfirmedOwner,
    AutomationCompatibleInterface
{
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(string reason);

    //* Type Declarations */
    enum RaffleState {
        OPEN,
        CALCULATING_WINNER
    }

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; // duration of lottery in seconds
    uint256 private s_lastTimestamp;
    address payable[] private s_players;
    address payable private s_recentWinner;
    RaffleState private s_raffleState;

    //** Chainlink VRF variables */
    uint64 private immutable i_subscriptionId;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    address s_owner;

    //** Events */
    event EnterRaffle(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) ConfirmedOwner(msg.sender) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimestamp = block.timestamp;

        // Chainlink VRF
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        s_owner = msg.sender;
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnterRaffle(msg.sender);
    }

    function fulfillRandomWords(
        uint256 /* _requestId */,
        uint256[] memory _randomWords
    ) internal override {
        // Checks
        // Effects (Our own contract)
        uint256 indexOfWinner = _randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimestamp = block.timestamp;
        emit WinnerPicked(winner);

        // Interactions (Other contracts)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * @dev This is the function that Chainlink Automation nodes will call to see if the upkeep needs to be performed.
     * @return upkeepNeeded
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool enoughTimeHasPassed = (block.timestamp - s_lastTimestamp) >=
            i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance >= 0;
        bool enoughPlayers = s_players.length > 0;

        upkeepNeeded =
            enoughTimeHasPassed &&
            isOpen &&
            enoughPlayers &&
            hasBalance;
        return (upkeepNeeded, "0x0");
    }

    /**
     * @dev This is the function that Chainlink Automation nodes will call if the upkeep is needed, decided by checkUpkeep, and if true picks the raffle winner.
     */
    function performUpkeep(bytes calldata /* performData */) external {
        // Checks
        (bool upkeepNeeded, ) = checkUpkeep("0x0");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                "Upkeep not needed. Check upkeep first."
            );
        }
        // Effects (Our own contract)
        s_raffleState = RaffleState.CALCULATING_WINNER;

        // Interactions (Other contracts)
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        emit RequestedRaffleWinner(requestId);
    }

    /** Getters */
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) public view returns (address payable) {
        return s_players[index];
    }

    function getRecentWinner() external view returns (address payable) {
        return s_recentWinner;
    }

    function getPlayers() external view returns (address payable[] memory) {
        return s_players;
    }

    function getLastTimestamp() external view returns (uint256) {
        return s_lastTimestamp;
    }
}
