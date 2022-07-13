#!/bin/sh

make -C certora munged

certoraRun \
    certora/munged/compound/PositionsManager.sol \
    certora/munged/compound/RewardsManager.sol \
    certora/munged/compound/InterestRatesManager.sol \
    certora/helpers/compound/contracts/DummyPoolTokenImpl.sol \
    certora/helpers/compound/contracts/DummyPoolTokenA.sol \
    certora/helpers/compound/contracts/DummyPoolTokenB.sol \
    certora/helpers/compound/contracts/SymbolicOracle.sol \
    certora/helpers/compound/contracts/SymbolicComptroller.sol \
    --link PositionsManager:comptroller=SymbolicComptroller \
    --link PositionsManager:interestRatesManager=InterestRatesManager \
    --verify PositionsManager:certora/spec/PositionsManagerCompound.spec \
    --loop_iter 2 \
    --solc solc8.13 \
    --optimistic_loop \
    --cache morpho \
    --rule "sanity" \
    --msg "PMFC Sanity $1" \
    --method 'liquidateLogic(address,address,address,uint256)' \
    --staging \
    --send_only \
    # --debug \
