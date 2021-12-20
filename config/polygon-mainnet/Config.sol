// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

contract Config {
    address dai = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    address aDai = 0x27F8D03b3a2196956ED754baDc28D73be8830A6e;
    address aUsdc = 0x1a13F4Ca1d028320A707D99520AbFefca3998b7F;

    address lendingPoolAddressesProviderAddress = 0xd05e3E715d945B59290df0ae8eF85c1BdB684744;

    mapping(address => uint8) slots;

    constructor() {
        slots[dai] = 0;
        slots[usdc] = 0;
    }
}
