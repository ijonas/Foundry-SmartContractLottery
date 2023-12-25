# Proveably Random Raffle Contracts

## About

This code is to create a proveably random smart contract lottery.

## How it works

1. Users can enter by paying for a ticket
  1. The ticket fees are going to the winner during the draw.
2. After X period of time, the lottery is closed and the draw is started.
  1. And this will be done programmatically.
3. Using Chainlink VRF & Chainlink Automation, for random numbers and time-based triggers respectively.
  1. The random number will be used to select the winner.
  2. The time-based trigger will be used to close the lottery and start the draw.


## How to run tests

    make test

or

    forge test -vvv --fork-url $SEPOLIA_RPC_URL

## How to deploy  

To Avil:

    make deploy 

To Sepolia:

    make deploy ARGS="--network sepolia"

To manage the lottery:

    make createSubscription ARGS="--network sepolia"
    make addConsumer ARGS="--network sepolia"
    make fundSubscription ARGS="--network sepolia"
