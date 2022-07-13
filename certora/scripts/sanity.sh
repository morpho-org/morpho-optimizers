#!/bin/sh

make -C certora munged

certoraRun \
    certora/munged/compound/PositionsManager.sol \
    certora/munged/compound/RewardsManager.sol \
    certora/munged/compound/InterestRatesManager.sol \
    certora/helpers/compound/DummyPoolTokenImpl.sol \
    certora/helpers/compound/DummyPoolTokenA.sol \
    certora/helpers/compound/DummyPoolTokenB.sol \
    certora/helpers/compound/SymbolicOracle.sol \
    certora/helpers/compound/SymbolicComptroller.sol \
    --link PositionsManager:comptroller=SymbolicComptroller \
    --link PositionsManager:interestRatesManager=InterestRatesManager \
    --verify PositionsManager:certora/spec/PositionsManagerCompound.spec \
    --loop_iter 2 \
    --optimistic_loop \
    --cache morpho \
    --rule "sanity" \
    --staging \
    --send_only \
    --msg "PMFC Sanity" \
