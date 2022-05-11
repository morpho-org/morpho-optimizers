
make -C certora munged

certoraRun \
    certora/harness/SwapManagerHarness.sol \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    --verify SwapManagerHarness:certora/spec/SwapManager.spec \
    --solc solc8.7                      \
    --solc_args '["--optimize"]' \
    --msg "SwapManager $1" \
    --send_only \
    $*

