
make -C certora munged

certoraRun \
    certora/harness/PositionsManagerForCompoundHarness.sol \
    certora/munged/compound/MarketsManagerForCompound.sol \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    certora/helpers/SymbolicOracle.sol \
    certora/helpers/SymbolicComptroller.sol \
    --link PositionsManagerForCompoundHarness:marketsManagerForCompound=MarketsManagerForCompound \
    --link PositionsManagerForCompoundHarness:compoundOracle=SymbolicOracle \
    --link PositionsManagerForCompoundHarness:comptroller=SymbolicComptroller \
    --verify PositionsManagerForCompoundHarness:certora/spec/PositionsManagerForCompound.spec \
    --solc solc8.7 \
    --path . \
    --solc_args '["--optimize"]' \
    --msg "PMFC $1" \
    --send_only \
    $*