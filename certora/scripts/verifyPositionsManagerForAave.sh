make -C certora munged

certoraRun \
    certora/harness/PositionsManagerForAaveHarness.sol \
    --verify PositionsManagerForAaveHarness:certora/spec/PositionsManagerForAave.spec \
    --solc solc8.7                      \
    --solc_args '["--optimize"]' \
    --msg "PMFA $1" \
    --send_only \
    --staging "alex/new-dt-hashing-alpha" \
    $*
