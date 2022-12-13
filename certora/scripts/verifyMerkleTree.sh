#!/bin/sh

make -C certora munged-rewards

certoraRun \
    certora/munged-rewards/common/rewards-distribution/MerkleTree.sol \
    --verify MerkleTree:certora/spec/MerkleTree.spec \
    --solc solc8.13 \
    --loop_iter 2 \
    --optimistic_loop \
    --settings -t=60\
    --staging \
    --msg "Merkle Tree" \
    --send_only \
    $@
