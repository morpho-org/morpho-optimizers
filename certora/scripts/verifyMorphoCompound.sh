make -C certora munged

certoraRun \
    certora/harness/compound/MorphoHarness.sol \
    --verify MorphoHarness:certora/spec/MorphoCompound.spec \
    --solc solc \
    --solc_args '["--optimize"]' \
    --msg "PMFA $1" \
    --send_only \
    --staging "alex/new-dt-hashing-alpha" \
    $*
