#!/bin/sh

certoraRun \
    certora/munged/compound/PositionsManager.sol \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    --verify PositionsManager:certora/helpers/complexity.spec \
    --staging \
    --optimistic_loop \
    --send_only \
    --msg "PositionsManager complexity check"
    
# to run for other scripts just copy the above and change lines #2, #5, and optionally #11 to match the given contract
# sometimes the below line is needed, doesn't seem to be in this case but left it for reference
# --packages @openzeppelin=node_modules/@openzeppelin \