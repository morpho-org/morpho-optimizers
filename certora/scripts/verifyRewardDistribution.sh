#!/bin/sh

make -C certora munged-rewards

certoraRun \
    certora/munged-rewards/common/rewards-distribution/RewardsDistributor.sol \
    certora/munged-rewards/common/rewards-distribution/MerkleTree.sol \
    --packages @rari-capital/solmate/=lib/solmate/ \
               @openzeppelin=node_modules/@openzeppelin \
    --verify RewardsDistributor:certora/spec/RewardsDistributor.spec \
    --solc solc8.13 \
    --loop_iter 2 \
    --optimistic_loop \
    --settings -t=60\
    --staging \
    --msg "Rewards Distributor" \
    --send_only \
    $@
