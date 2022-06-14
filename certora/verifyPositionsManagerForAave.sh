make -C certora munged

certoraRun contracts/aave/PositionsManagerForAave.sol \
           contracts/aave/positions-manager-parts/PositionsManagerForAaveStorage.sol \
--verify PositionsManagerForAave:certora/PositionsManagerForAave.spec \
--optimistic_loop --loop_iter 1 \
--solc_map PositionsManagerForAave=solc8.13,PositionsManagerForAaveStorage=solc8.7 \
--settings -t=600,-postProcessCounterExamples=true \
--msg "sanity"