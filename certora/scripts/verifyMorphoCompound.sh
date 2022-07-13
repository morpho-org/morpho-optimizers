#!/bin/sh

make -C certora munged

certoraRun \
    certora/harness/compound/MorphoHarness.sol \
    --verify MorphoHarness:certora/spec/MorphoCompound.spec \
    --solc_args '["--optimize"]' \
    --send_only \
    --msg "MorphoCompound $1"
