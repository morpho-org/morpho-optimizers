#!/bin/sh

make -C certora munged-rewards

certoraRun \
    certora/munged-rewards/common/rewards-distribution/RewardsDistributor.sol \
    certora/munged-rewards/common/rewards-distribution/MerkleTreeMock.sol \
    certora/munged-rewards/common/rewards-distribution/dependencies/MorphoToken.sol \
    certora/munged-rewards/common/rewards-distribution/dependencies/MerkleProof.sol \
    --packages @rari-capital/solmate=lib/solmate \
               @openzeppelin=node_modules/@openzeppelin \
    --verify RewardsDistributor:certora/spec/RewardsDistributor.spec \
    --solc solc8.13 \
    --loop_iter 2 \
    --optimistic_loop \
    --cloud yoav/grounding \
    --settings -t=60,-enableEqualitySaturation=false,-simplificationDepth=10,-s=z3\
    --msg "Rewards Distributor" \
    --send_only \
    --rule_sanity \
    $@
