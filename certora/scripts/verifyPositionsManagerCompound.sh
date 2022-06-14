# runs all of the PositionsManagerCompound.spec file

make -C certora munged

certoraRun \
    certora/harness/compound/PositionsManagerHarness.sol \
    certora/helpers/compound/DummyPoolTokenImpl.sol \
    certora/helpers/compound/DummyPoolTokenA.sol \
    certora/helpers/compound/DummyPoolTokenB.sol \
    certora/helpers/compound/SymbolicOracle.sol \
    --verify PositionsManagerHarness:certora/spec/PositionsManagerCompound.spec \
    --solc solc8.7 \
    --loop_iter 2 \
    --optimistic_loop \
    --cache morpho \
    --msg "PMFC $1"


    # notes:
    # keep the cache name common among run scripts, will save a bunch on the setup time 
    # (pre processing the contracts and specs before submitting to the solver)