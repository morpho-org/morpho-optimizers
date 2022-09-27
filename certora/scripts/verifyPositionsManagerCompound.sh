#!/bin/sh
# runs all of the PositionsManagerCompound.spec file

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
    certora/helpers/DummyWeth.sol \
    --packages @morpho-labs/morpho-utils/=lib/morpho-utils/src/ \
               @rari-capital/solmate/=lib/solmate/ \
               @openzeppelin=node_modules/@openzeppelin \
    --link PositionsManagerHarness:comptroller=SymbolicComptroller \
    --link PositionsManagerHarness:interestRatesManager=InterestRatesManager \
    --verify PositionsManagerHarness:certora/spec/PositionsManagerCompound.spec \
    --solc solc8.13 \
    --loop_iter 2 \
    --optimistic_loop \
    --settings -t=60\
    --cache morpho \
    --staging \
    --msg "PositionsManager For Compound: $1" \
    --send_only \

    # --method 'repayLogic(address, address, address, uint256, uint256)' \

    # notes:
    # keep the cache name common among run scripts, will save a bunch on the setup time 
    # (pre processing the contracts and specs before submitting to the solver)

        # certora/harness/compound/PositionsManagerHarness.sol \
