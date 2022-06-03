// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

contract Config {
    address aave = 0xD6DF932A45C0f255f85145f286eA0b292B21C90B;
    address dai = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address usdt = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address wbtc = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
    address wEth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    address aAave = 0x1d2a0E5EC8E5bBDCA5CB219e649B565d8e5c3360;
    address aDai = 0x27F8D03b3a2196956ED754baDc28D73be8830A6e;
    address aUsdc = 0x1a13F4Ca1d028320A707D99520AbFefca3998b7F;
    address aUsdt = 0x60D55F02A771d515e077c9C2403a1ef324885CeC;
    address aWbtc = 0x5c2ed810328349100A66B82b78a1791B101C9D61;
    address aWeth = 0x28424507fefb6f7f8E9D3860F56504E4e5f5f390;
    address aWmatic = 0x8dF3aad3a84da6b69A4DA8aeC3eA40d9091B2Ac4;

    address stableDebtDai = 0x2238101B7014C279aaF6b408A284E49cDBd5DB55;
    address variableDebtDai = 0x75c4d1Fb84429023170086f06E682DcbBF537b7d;
    address variableDebtUsdc = 0x248960A9d75EdFa3de94F7193eae3161Eb349a12;

    address lendingPoolAddressesProviderAddress = 0xd05e3E715d945B59290df0ae8eF85c1BdB684744;
    address protocolDataProviderAddress = 0x7551b5D2763519d4e37e8B81929D336De671d46d;
    address aaveIncentivesControllerAddress = 0x357D51124f59836DeD84c8a1730D72B749d8BC23;
    address swapRouterAddress = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    uint24 MORPHO_UNIV3_FEE = 3000;
    uint24 REWARD_UNIV3_FEE = 3000;
}
