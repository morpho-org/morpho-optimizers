// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

contract Config {
    address constant aave = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant wEth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant comp = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address constant bat = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
    address constant tusd = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address constant uni = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant zrx = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
    address constant link = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant mkr = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address constant fei = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
    address constant yfi = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address constant usdp = 0x8E870D67F660D95d5be530380D0eC0bd388289E1;
    address constant sushi = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;

    address constant aAave = 0xFFC97d72E13E01096502Cb8Eb52dEe56f74DAD7B;
    address constant aDai = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address constant aUsdc = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address constant aUsdt = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address constant aWbtc = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656;
    address constant aWeth = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;

    address constant wrappedNativeToken = wEth;
    address constant aWrappedNativeToken = aWeth;

    address constant stableDebtDai = 0x778A13D3eeb110A4f7bb6529F99c000119a08E92;
    address constant variableDebtDai = 0x1852DC24d1a8956a0B356AA18eDe954c7a0Ca5ae;
    address constant variableDebtUsdc = 0x619beb58998eD2278e08620f97007e1116D5D25b;

    address constant poolAddressesProviderAddress = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    address constant aaveIncentivesControllerAddress = 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5;
    address constant swapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
}
