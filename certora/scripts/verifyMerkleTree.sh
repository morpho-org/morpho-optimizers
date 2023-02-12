#!/bin/sh

make -C certora munged-rewards

certoraRun \
    certora/munged-rewards/common/rewards-distribution/MerkleTreeMock.sol \
    --packages @rari-capital/solmate=lib/solmate \
               @openzeppelin=node_modules/@openzeppelin \
    --verify MerkleTreeMock:certora/spec/MerkleTree.spec \
    --solc solc8.13 \
    --loop_iter 2 \
    --optimistic_loop \
    --settings -t=60\
    --msg "Merkle Tree" \
    --send_only \
    $@
