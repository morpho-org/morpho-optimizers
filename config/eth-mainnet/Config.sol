// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

contract Config {
    address public aave = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public wEth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public comp = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public bat = 0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E;

    // Aave

    address public aAave = 0xFFC97d72E13E01096502Cb8Eb52dEe56f74DAD7B;
    address public aDai = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address public aUsdc = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address public aUsdt = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address public aWbtc = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656;
    address public aWeth = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;

    address public stableDebtDai = 0x778A13D3eeb110A4f7bb6529F99c000119a08E92;
    address public variableDebtDai = 0x1852DC24d1a8956a0B356AA18eDe954c7a0Ca5ae;
    address public variableDebtUsdc = 0x619beb58998eD2278e08620f97007e1116D5D25b;

    address public poolAddressesProviderAddress = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    address public aaveIncentivesControllerAddress = 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5;
    address public swapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Compound

    address public cAave = 0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c;
    address public cDai = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public cUsdc = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address public cUsdt = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address public cWbtc = 0xC11b1268C1A384e55C48c2391d8d480264A3A7F4;
    address public cEth = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address public cBat = 0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E;

    address public comptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    // Swap Manager Config

    uint24 public MORPHO_UNIV3_FEE = 3000;
    uint24 public REWARD_UNIV3_FEE = 10000;
}
