// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

contract Config {
    address aave = 0x953af320e2bD3041c4e56BB3a30E7f613a1f3C1A;
    address dai = 0x2Ec4c6fCdBF5F9beECeB1b51848fc2DB1f3a26af;
    address usdc = 0x5B8B635c2665791cf62fe429cB149EaB42A3cEd8;
    address usdt = 0xa0704bfa9E17cF4a1d74A60db7bcdA1B5D00D3E6;
    address wbtc = 0x37022F97333df61A61595B7cf43b63205290f8Ee;
    address weth = 0x98a5F1520f7F7fb1e83Fe3398f9aBd151f8C65ed;

    address aAave = 0x335DC27c7C57A2eAf43BDD4DcD0F3d6D2Ee0B496;
    address aDai = 0x43E8058dFA2dDea046180E1c57A41a1760E4AC60;
    address aUsdc = 0xD624c05a873B9906e5F1afD9c5d6B2dC625d36c3;
    address aUsdt = 0x6250D823779d7456B1b15e80F151707610646Fe5;
    address aWbtc = 0xfdC6350fff39f2095659B07A7d2B6dbd21607D9E;
    address aWeth = 0xb7eca5eAA51c678B97AE671df511bDdE2CE99896;

    address variableDebtDai = 0xBA123803a774F01492CE9d84db714eb7897f431c;
    address variableDebtUsdc = 0x7f7D85EC65b50FB50527F784A702e35cE4e76111;

    address poolAddressesProviderAddress = 0xA55125A90d75a95EC00130E8E8C197dB5641Eb19;
    address aaveIncentivesControllerAddress = 0x2af4dea830111931ad60023479Eb88f2bA9062aa;
    // address swapRouterAddress = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    uint24 MORPHO_UNIV3_FEE = 3000;
    uint24 REWARD_UNIV3_FEE = 3000;
}
