// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.0;

contract Config {
    address constant aave = 0x63a72806098Bd3D9520cC43356dD78afe5D386D9;
    address constant dai = 0xd586E7F844cEa2F87f50152665BCbc2C279D8d70;
    address constant usdc = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address constant usdt = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
    address constant wbtc = 0x50b7545627a5162F82A992c33b87aDc75187B218;
    address constant wEth = 0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB;
    address constant wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    address constant aAave = 0xf329e36C7bF6E5E86ce2150875a84Ce77f477375;
    address constant aDai = 0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE;
    address constant aUsdc = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address constant aUsdt = 0x6ab707Aca953eDAeFBc4fD23bA73294241490620;
    address constant aWbtc = 0x078f358208685046a11C85e8ad32895DED33A249;
    address constant aWeth = 0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8;
    address constant avWavax = 0x6d80113e533a2C0fe82EaBD35f1875DcEA89Ea97;

    address constant wrappedNativeToken = wavax;
    address constant aWrappedNativeToken = avWavax;
    address constant rewardToken = wavax;

    address constant stableDebtDai = 0xd94112B5B62d53C9402e7A60289c6810dEF1dC9B;
    address constant variableDebtDai = 0x8619d80FB0141ba7F184CbF22fd724116D9f7ffC;
    address constant variableDebtUsdc = 0xFCCf3cAbbe80101232d343252614b6A3eE81C989;

    address constant poolDataProviderAddress = 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654;
    address constant poolAddressesProviderAddress = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
    address constant rewardsControllerAddress = 0x929EC64c34a17401F460460D4B9390518E5B473e;
    address constant swapRouterAddress = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
}
