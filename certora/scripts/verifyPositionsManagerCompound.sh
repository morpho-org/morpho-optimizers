#!/bin/sh
# runs all of the PositionsManagerCompound.spec file

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
    --solc solc \
    --loop_iter 2 \
    --optimistic_loop \
    --cache morpho \
    --staging \
    --send_only \

    # --method 'liquidateLogic(address, address, address, uint256)' \
    # --method 'repayLogic(address, address, address, uint256, uint256)' \

    # notes:
    # keep the cache name common among run scripts, will save a bunch on the setup time 
    # (pre processing the contracts and specs before submitting to the solver)

        # certora/harness/compound/PositionsManagerHarness.sol \