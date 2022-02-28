// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

contract Config {
    address aave = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address aAave = 0xFFC97d72E13E01096502Cb8Eb52dEe56f74DAD7B;
    address aDai = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address aUsdc = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address aUsdt = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address aWbtc = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656;
    address aWeth = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;

    address variableDebtDai = 0x1852DC24d1a8956a0B356AA18eDe954c7a0Ca5ae;
    address variableDebtUsdc = 0x848c080d2700CBE1B894a3374AD5E887E5cCb89c;

    address lendingPoolAddressesProviderAddress = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    address protocolDataProviderAddress = 0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d;
    address aaveIncentivesControllerAddress = 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5;
    address swapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

<<<<<<< HEAD
    uint24 morphoPoolFee = 3000;
    uint24 rewardPoolFee = 10000;
=======
    mapping(address => uint8) slots;

    constructor() {
        slots[dai] = 2;
        slots[usdc] = 9;
        slots[wbtc] = 0;
        slots[usdt] = 2;
        slots[weth] = 3;
    }
>>>>>>> 6d98522 (🔧✅ Update conf and tests for mainnet)
}
