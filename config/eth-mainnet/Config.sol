// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

contract Config {
    address public aave = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public wEth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public comp = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public bat = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
    address public tusd = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address public uni = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address public zrx = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
    address public link = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public mkr = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address public fei = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
    address public yfi = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address public usdp = 0x8E870D67F660D95d5be530380D0eC0bd388289E1;
    address public sushi = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;

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

    address public lendingPoolAddressesProviderAddress = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    address public protocolDataProviderAddress = 0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d;
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
    address public cTusd = 0x12392F67bdf24faE0AF363c24aC620a2f67DAd86;
    address public cUni = 0x35A18000230DA775CAc24873d00Ff85BccdeD550;
    address public cComp = 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4;
    address public cZrx = 0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407;
    address public cLink = 0xFAce851a4921ce59e912d19329929CE6da6EB0c7;
    address public cMkr = 0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b;
    address public cFei = 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67;
    address public cYfi = 0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946;
    address public cUsdp = 0x041171993284df560249B57358F931D9eB7b925D;
    address public cSushi = 0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7;

    address public comptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    // Swap Manager Config

    uint24 public MORPHO_UNIV3_FEE = 3000;
    uint24 public REWARD_UNIV3_FEE = 10000;
}
