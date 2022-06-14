# runs all of the PositionsManagerCompound.spec file

make -C certora munged

certoraRun \
    certora/harness/compound/PositionsManagerHarness.sol \
    --verify PositionsManagerHarness:certora/spec/PositionsManagerCompound.spec \
    --solc solc8.7 \
    --loop_iter 2 \
    --optimistic_loop \
    --cache morpho \
    --msg "PMFC $1"