#!/bin/sh

make -C certora munged

certoraRun \
    certora/harness/compound/PositionsManagerHarness.sol \
    certora/munged/compound/RewardsManager.sol \
    certora/munged/compound/InterestRatesManager.sol \
    certora/helpers/compound/contracts/DummyPoolTokenImpl.sol \
    certora/helpers/compound/contracts/DummyPoolTokenA.sol \
    certora/helpers/compound/contracts/DummyPoolTokenB.sol \
    certora/helpers/compound/contracts/SymbolicOracle.sol \
    certora/helpers/compound/contracts/SymbolicComptroller.sol \
    --link PositionsManagerHarness:comptroller=SymbolicComptroller \
    --link PositionsManagerHarness:interestRatesManager=InterestRatesManager \
    --verify PositionsManagerHarness:certora/spec/PositionsManagerCompound.spec \
    --solc solc \
    --loop_iter 2 \
    --optimistic_loop \
    --cache morpho \
    --rule "sanity" \
    --msg "PMFC Sanity $1" \
    --send_only \
    # --debug \
