// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {Raffle} from "../src/Raffle.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , , , , uint256 deployerKey) = helperConfig
            .s_activeNetworkConfig();
        return createSubscription(vrfCoordinator, deployerKey);
    }

    function createSubscription(
        address vrfCoordinator,
        uint256 deployerKey
    ) public returns (uint64) {
        console.log("Creating a subscriptiob on ChainId: %s", block.chainid);
        vm.startBroadcast(deployerKey);

        VRFCoordinatorV2Mock mock = VRFCoordinatorV2Mock(vrfCoordinator);
        uint64 subscriptionId = mock.createSubscription();

        vm.stopBroadcast();
        console.log("Your subscriptionId is: %s", subscriptionId);
        return subscriptionId;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant LINK_AMOUNT = 3 ether;

    function fundSubscription(
        address vrfCoordinator,
        uint64 subscriptionId,
        address linkToken,
        uint256 deployerKey
    ) public returns (uint64) {
        console.log(
            "Funding a subscription %s on ChainId: %s",
            subscriptionId,
            block.chainid
        );

        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2Mock mock = VRFCoordinatorV2Mock(vrfCoordinator);
            mock.fundSubscription(subscriptionId, LINK_AMOUNT);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();

            LinkToken(linkToken).transferAndCall(
                vrfCoordinator,
                LINK_AMOUNT,
                abi.encode(subscriptionId)
            );
            vm.stopBroadcast();
        }

        // console.log("Your subscriptionId is: %s", subscriptionId);
        return 0;
    }

    function fundSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 subscriptionId,
            ,
            address linkToken,
            uint256 deployerKey
        ) = helperConfig.s_activeNetworkConfig();
        return
            fundSubscription(
                vrfCoordinator,
                subscriptionId,
                linkToken,
                deployerKey
            );
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function run() external {
        address contractAddress = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        Raffle raffle = Raffle(contractAddress);
        addConsumerUsingConfig(raffle);
    }

    function addConsumerUsingConfig(Raffle raffle) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 subscriptionId,
            ,
            ,
            uint256 deployerKey
        ) = helperConfig.s_activeNetworkConfig();

        addConsumer(raffle, subscriptionId, vrfCoordinator, deployerKey);
    }

    function addConsumer(
        Raffle raffle,
        uint64 subscriptionId,
        address vrfCoordinatorAddress,
        uint256 deployerKey
    ) public {
        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock vrfCoordinator = VRFCoordinatorV2Mock(
            vrfCoordinatorAddress
        );
        vrfCoordinator.addConsumer(subscriptionId, address(raffle));
        vm.stopBroadcast();
    }
}
