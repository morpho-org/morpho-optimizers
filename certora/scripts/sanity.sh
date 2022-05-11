
make -C certora munged

certoraRun \
    certora/harness/SwapManagerHarness.sol \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    --packages @uniswap=node_modules/@uniswap \
               @openzeppelin=node_modules/@openzeppelin \
    --verify SwapManagerHarness:certora/spec/sanity.spec \
    --rule sanity \
    --solc solc \
    --loop_iter 2 \
    --solc_args '["--optimize"]' \
    --settings -t=60 \
    --msg "sanity" \
    --send_only \
    $*
