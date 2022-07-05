# runs all of the PositionsManagerCompound.spec file

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
    --method 'liquidateLogic(address,address,address,uint256)' \
    --solc solc8.13 \
    --loop_iter 2 \
    --optimistic_loop \
    --cache morpho \
    --msg "PMFC $1" \
    --staging \


    # notes:
    # keep the cache name common among run scripts, will save a bunch on the setup time 
    # (pre processing the contracts and specs before submitting to the solver)

        # certora/harness/compound/PositionsManagerHarness.sol \