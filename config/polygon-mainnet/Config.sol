// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

contract Config {
    address aave = 0xD6DF932A45C0f255f85145f286eA0b292B21C90B;
    address dai = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address usdt = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    address aAave = 0x1d2a0E5EC8E5bBDCA5CB219e649B565d8e5c3360;
    address aDai = 0x27F8D03b3a2196956ED754baDc28D73be8830A6e;
    address aUsdc = 0x1a13F4Ca1d028320A707D99520AbFefca3998b7F;
    address aWeth = 0x28424507fefb6f7f8E9D3860F56504E4e5f5f390;

    address variableDebtDai = 0x75c4d1Fb84429023170086f06E682DcbBF537b7d;
    address variableDebtUsdc = 0x248960A9d75EdFa3de94F7193eae3161Eb349a12;

    address lendingPoolAddressesProviderAddress = 0xd05e3E715d945B59290df0ae8eF85c1BdB684744;
    address protocolDataProviderAddress = 0x7551b5D2763519d4e37e8B81929D336De671d46d;

    mapping(address => uint8) slots;

    constructor() {
        // A tool to find the slot of tokens' balance: https://github.com/kendricktan/slot20
        slots[dai] = 0;
        slots[usdc] = 0;
    }
}
